-- $Id: Openbus.lua 90798 2009-04-23 02:06:47Z augusto $

local oil = require "oil"
local oop = require "loop.base"
local lce = require "lce"
local log = require "openbus.util.Log"
local CredentialManager = require "openbus.util.CredentialManager"
local Utils = require "openbus.util.Utils"
local LeaseRenewer = require "openbus.lease.LeaseRenewer"
local OilUtilities = require "openbus.util.OilUtilities"
local smartpatch = require "openbus.faulttolerance.smartpatch"
local SmartComponent = require "openbus.faulttolerance.SmartComponent"

local pairs = pairs
local os = os
local loadfile = loadfile
local assert = assert
local require = require
local print = print

---
-- API de acesso a um barramento OpenBus.
---
module "openbus.Openbus"

Openbus = oop.class {
  ---
  -- A instância única do barramento.
  ---
  _instance = nil,
  ---
  -- O ORB.
  ---
  orb = nil,
  ---
  -- Indica se o ORB já foi finalizado.
  ---
  isORBFinished = true,
  ---
  -- O host do Serviço de Controle de Acesso.
  ---
  host = nil,
  ---
  -- A porta do Serviço de Controle de Acesso.
  ---
  port = -1,
  ---
  -- O Serviço de Controle de Acesso.
  ---
  acs = nil,
  ---
  -- Interface ILeaseProvider do Serviço de Controle de Acesso.
  ---
  lp = nil,
  ---
  -- Interface IComponent do Serviço de Controle de Acesso.
  ---
  ic = nil,
  ---
  -- Interface IFaultTolerantService do Serviço de Controle de Acesso.
  ---
  ft = nil,  
  ---
  -- O renovador do <i>lease</i>.
  ---
  leaseRenewer = nil,
  ---
  -- <i>Callback</i> para a notificação de que um <i>lease</i> expirou.
  ---
  leaseExpiredCallback = nil,
  ---
  -- Serviço de registro.
  ---
  rgs = nil,
  ---
  -- Serviço de sessão.
  ---
  ss = nil,
  ---
  -- Interceptador servidor.
  ---
  serverInterceptor = nil,
  ---
  -- Configuração do interceptador servidor.
  ---
  serverInterceptorConfig = nil,
  ---
  -- Interceptador cliente.
  ---
  clientInterceptor = nil,
  ---
  -- Configuração do interceptador cliente.
  ---
  clientInterceptorConfig = nil,
  ---
  -- Credencial recebida ao se conectar ao barramento.
  ---
  credentialManager = nil,
  ---
  -- O slot da credencial da requisição.
  ---
  requestCredentialSlot = -1,
  ---
  -- Indica o estado da conexão. 1 = conectado, 2 = desconectado
  ---
  connectionState = 2,
  ---
  -- Indica se o mecanismo de tolerancia a falhas esta ativo
  ---
  isFaultToleranceEnable = false,

  smartACS = nil,

  ---
  -- Guarda os métodos que não devem ser interceptados.
  -- Política padrão é de interceptar todos.
  ---
  ifaceMap = nil,

}

---
-- Fornece a instância única do barramento.
--
--@return A instância única do barramento.
---
function Openbus:__init()
  if not self._instance then
    self._instance = oop.rawnew(self, {})
  end
  return self._instance
end

---
-- Retorna ao seu estado inicial, ou seja, desfaz as definições de atributos
-- realizadas.
---
function Openbus:_reset()
  self.credentialManager = nil
  self.requestCredentialSlot = -1
  if not self.isORBFinished and self.orb then
    self:finish()
  end
  self.orb = nil
  self.rootPOA = nil
  self.isORBFinished = true
  self.acs = nil
  self.host = nil
  self.port = -1
  self.lp = nil
  self.ic = nil
  self.ft = nil
  self.leaseRenewer = nil
  self.leaseExpiredCallback = nil
  self.rgs = nil
  self.ss = nil
  self.serverInterceptor = nil
  self.serverInterceptorConfig = nil
  self.clientInterceptor = nil
  self.clientInterceptorConfig = nil
  self.connectionState = 2
  self.isFaultToleranceEnable = false
  self.smartACS = nil
  self.ifaceMap = {}
end

---
-- Cadastra os interceptadores cliente e servidor no ORB.
---
function Openbus:_setInterceptors()
  self.credentialManager = CredentialManager()
  local config
  if not self.serverInterceptorConfig or not self.clientInterceptorConfig then
    local DATA_DIR = os.getenv("OPENBUS_DATADIR")
    config = assert(loadfile(DATA_DIR ..
      "/conf/advanced/InterceptorsConfiguration.lua"))()
  end
  self.serverInterceptor = ServerInterceptor(self.serverInterceptorConfig or
    config, self.acs)
  self.orb:setserverinterceptor(self.serverInterceptor)
  self.clientInterceptor = ClientInterceptor(self.clientInterceptorConfig or
    config, self.credentialManager)
  self.orb:setclientinterceptor(self.clientInterceptor)
end


---
-- Obtém as facetas do Serviço de Controle de Acesso. Este
-- método também instancia um observador de <i>leases</i>.
--
-- @return {@code false} caso ocorra algum erro, {@code true} caso contrário.
---
function Openbus:_fetchACS()

  local status, acs, lp, ft, ic 
  
  if self.isFaultToleranceEnable then
  	status, services = self.smartACS:_fetchSmartComponent()
  else
    status, acs, lp, ic, ft = oil.pcall(Utils.fetchAccessControlService, self.orb, self.host, self.port)
  end
  
  if not status then
		log:error("Erro ao obter as facetas do Serviço de Controle de Acesso." ..
		  "Erro: " .. acs)
		return false
  end
  if (self.isFaultToleranceEnable and not services) or 
  	 (not self.isFaultToleranceEnable and not acs) then
		-- o erro já foi pego e logado
		return false
  end
  
  if self.isFaultToleranceEnable then
  	acs = services[Utils.ACCESS_CONTROL_SERVICE_KEY]
    lp = services[Utils.LEASE_PROVIDER_KEY]
    ic = services[Utils.ICOMPONENT_KEY]
    ft = services[Utils.FAULT_TOLERANT_ACS_KEY]
  end
  
  self.acs, self.lp, self.ic, self.ft = acs, lp, ic, ft

  local status, err = oil.pcall(self._setInterceptors, self)
  if not status then
    log:error("Erro ao cadastrar interceptadores no ORB. Erro: " .. err)
    return false
  end
  return true
end

---
-- Carrega as IDLs dos serviços básicos e do SCS.
---
function Openbus:_loadIDLs()
  local IDLPATH_DIR = os.getenv("IDLPATH_DIR")
  if not IDLPATH_DIR then
    log:error("Openbus: A variável IDLPATH_DIR não foi definida.")
    return false
  end
  local idlfile = IDLPATH_DIR .. "/scs.idl"
  self.orb:loadidlfile(idlfile)
  idlfile = IDLPATH_DIR .. "/access_control_service.idl"
  self.orb:loadidlfile(idlfile)
  idlfile = IDLPATH_DIR .. "/registry_service.idl"
  self.orb:loadidlfile(idlfile)
  idlfile = IDLPATH_DIR .. "/session_service.idl"
  self.orb:loadidlfile(idlfile)
  idlfile = IDLPATH_DIR .. "/ft_service.idl"
  self.orb:loadidlfile(idlfile)
  idlfile = IDLPATH_DIR .. "/ft_service_monitor.idl"
  self.orb:loadidlfile(idlfile)
--  idlfile = IDLPATH_DIR .. "/data_service.idl"
--  self.orb:loadidlfile(idlfile)
  return true
end

---
-- Finaliza o procedimento de conexão, após um login bem sucedido. Salva a
-- credencial e inicia o processo de renovação de lease.
--
-- @param credential A credencial do membro.
-- @param lease O período de tempo entre as renovações do lease.
--
-- @return O serviço de registro. {@code false} caso ocorra algum erro.
---
function Openbus:_completeConnection(credential, lease)
  self.credentialManager:setValue(credential)
  self.leaseRenewer = LeaseRenewer(
    lease, credential, self.lp, self.leaseExpiredCallback)
  self.leaseRenewer:startRenew()
  self.connectionState = 1
  if not self.rgs then
  	self.rgs = self.acs:getRegistryService()
  end
  return self.rgs
end

---
-- Habilita o mecanismo de tolerancia a falhas
--
function Openbus:enableFaultTolerance()
    log:faulttolerance("Mecanismo de tolerancia a falhas sendo habilitado...")
    if not self.orb then
       log:error("OpenBus: O orb precisa ser inicializado.")
       return false
    end 
    
    if not self.isFaultToleranceEnable then
    	local DATA_DIR = os.getenv("OPENBUS_DATADIR")
    	local ftconfig = assert(loadfile(DATA_DIR .."/conf/FaultToleranceConfiguration.lua"))()
    	local keys = {}
    	keys[Utils.ACCESS_CONTROL_SERVICE_KEY] = { interface = "IDL:openbusidl/acs/IAccessControlService:1.0",
    												  hosts = ftconfig.hosts.ACS, }
    	keys[Utils.LEASE_PROVIDER_KEY] = { interface = "IDL:openbusidl/acs/ILeaseProvider:1.0",
    										  hosts = ftconfig.hosts.LP, }
    	keys[Utils.ICOMPONENT_KEY] = { interface = "IDL:scs/core/IComponent:1.0",
    									  hosts = ftconfig.hosts.ACSIC, }
    	keys[Utils.FAULT_TOLERANT_ACS_KEY] = { interface = "IDL:openbusidl/ft/IFaultTolerantService:1.0",
    									  		  hosts = ftconfig.hosts.FTACS, }

    	self.smartACS = SmartComponent:__init(self.orb, "ACS", keys)
    	
    end

	self.isFaultToleranceEnable = true
	return true
end

---
-- Retorna o barramento para o seu estado inicial, ou seja, desfaz as
-- definições de atributos realizadas. Em seguida, inicializa o Orb.
--
-- @param host Endereço do Serviço de Controle de Acesso.
-- @param port Porta do Serviço de Controle de Acesso.
-- @param props Conjunto de propriedades para a criação do ORB.
-- @param serverInterceptorConfig Configuração opcional do interceptador
--        servidor.
-- @param clientInterceptorConfig Configuração opcional do interceptador
--        cliente.
--
-- @return {@code false} caso ocorra algum erro, {@code true} caso contrário.
---
function Openbus:resetAndInitialize(host, port, props, serverInterceptorConfig,
  clientInterceptorConfig)
  if not host then
    log:error("OpenBus: O campo 'host' não pode ser nil")
    return false
  end
  if not port or port < 0 then
    log:error("OpenBus: O campo 'port' não pode ser nil nem negativo.")
    return false
  end
  self:_reset()
  -- init
  self.host = host
  self.port = port
  self.serverInterceptorConfig = serverInterceptorConfig
  self.clientInterceptorConfig = clientInterceptorConfig
  -- configuração do OiL
  if not props then
    props = {}
  end
  if not props.tcpoptions then
    props.tcpoptions = {}
  end
  if not props.tcpoptions.reuseaddr then
    props.tcpoptions.reuseaddr = true
  end
  if not props.flavor then
    props.flavor = "intercepted;corba;typed;cooperative;base"
  end
  self.orb = oil.init(props)
  --TODO: remover esse uso de oil.orb no Openbus e mover os requires abaixo para
  --      o topo.
  oil.orb = self.orb
  ClientInterceptor = require "openbus.interceptors.ClientInterceptor"
  ServerInterceptor = require "openbus.interceptors.ServerInterceptor"
  -- carrega IDLs
  local status, err = oil.pcall(self._loadIDLs, self)
  if not status then
    log:error("OpenBus: Erro ao carregar as IDLs. Erro: " .. err)
    return false
  end
  return err
end

---
-- Fornece o ORB.
--
-- @return O ORB.
---
function Openbus:getORB()
  return self.orb
end

---
-- Executa o ORB.
---
function Openbus:run()
  oil.newthread(self.orb.run, self.orb)
end

---
-- Finaliza a execução do ORB.
---
function Openbus:finish()
  if not self.orb then
    return
  end
  self.orb:shutdown()
  self.isORBFinished = true
end

---
-- Fornece o Serviço de Controle de Acesso.
-- Caso esteja em estado de falha e o mecanismo de tolerancia a falhas esteja ativado,
-- obtem outra réplica ativa
--
-- @return O Serviço de Controle de Acesso.
---
function Openbus:getAccessControlService()

  if self.acs and self.isFaultToleranceEnable then
  	if not OilUtilities:existent(self.acs)  then
      if not self:_fetchACS() then
        log:error("OpenBus: Não foi possível acessar o servico de controle de acesso.")
        return false
      end
    end
  end
  return self.acs
end

function Openbus:getACSIComponent()
  if self.ic and self.isFaultToleranceEnable then
  	if not OilUtilities:existent(self.ic)  then
      if not self:_fetchACS() then
        log:error("OpenBus: Não foi possível acessar o servico de controle de acesso.")
        return false
      end
    end
  end
  return self.ic
end



---
-- Fornece o Serviço de Sessão. Caso o Openbus ainda não tenha a referência
-- para o Serviço de Sessão, obtém a mesma a partir do Serviço de Registro.
--
-- @return O Serviço de Sessão. Nil caso ainda não tenha sido obtida uma
--         referência e o Serviço de Controle de Acesso estiver inacessível.
---
function Openbus:getSessionService()
  if not self.rgs then
  	local registryService = self.acs:getRegistryService()
  	self.rgs = self.orb:narrow(registryService,
                    "IDL:openbusidl/rs/IRegistryService:1.0")
  end
  if not self.ss and self.rgs then
    local facets = { Utils.SESSION_SERVICE_FACET_NAME }
    local offers = self.rgs.find(facets)
    if not offers or #offers > 0 then
      local component = self.orb:narrow(offers[1].member)
      local facet = component:getFacet(Utils.SESSION_SERVICE_INTERFACE)
      if not facet then
        return nil
      end
      self.ss = self.orb:narrow(facet)
      return self.ss
    end
    return nil
  end
  return self.ss
end

---
-- Fornece a credencial da entidade.
--
-- @return A credencial.
---
function Openbus:getCredential()
  if not self.credentialManager then
    return nil
  end
  return self.credentialManager:getValue()
end

---
-- Configura a credencial da entidade.
--
-- @param credential A nova credencial
---
function Openbus:setCredential(credential)
  if self.credentialManager then
    self.credentialManager:setValue(credential)
  end
end

---
-- Define uma credencial a ser utilizada no lugar da credencial corrente. Útil
-- para fornecer uma credencial com o campo delegate preenchido.
--
-- @param credential Credencial a ser usada nas requisições a serem
--        realizadas.
---
function Openbus:setThreadCredential(credential)
  self.credentialManager:setThreadValue(credential)
end

---
-- Fornece a credencial interceptada a partir da requisição atual.
--
-- @return A credencial da requisição.
---
function Openbus:getInterceptedCredential()
  if not self.serverInterceptor then
    return nil
  end
  return self.serverInterceptor:getCredential()
end

---
-- Realiza uma tentativa de conexão com o barramento (serviço de controle de
-- acesso e o serviço de registro), via nome de usuário e senha.
--
-- @param user Nome do usuário.
-- @param password Senha do usuário.
--
-- @return O serviço de registro. {@code false} caso ocorra algum erro.
--
-- @throws InvalidCredentialException Caso a credencial seja rejeitada ao
--         tentar obter o Serviço de Registro.
---
function Openbus:connect(user, password)
  if not user or not password then
    log:error("OpenBus: Os parâmetros 'user' e 'password' não podem ser nil.")
    return false
  end
  if self.connectionState == 2 then
    if not self.acs then
      if not self:_fetchACS() then
        log:error("OpenBus: Não foi possível acessar o barramento.")
        return false
      end
    end
    local success, credential, lease = self.acs:loginByPassword(user, password)
    if success then
      return self:_completeConnection(credential, lease)
    else
      log:error("OpenBus: Não foi possível conectar ao barramento.")
      return false
    end
  else
    log:error("OpenBus: O barramento já está conectado.")
    return false
  end
end

---
-- Realiza uma tentativa de conexão com o barramento (serviço de controle de
-- acesso e o serviço de registro), via certificado.
--
-- @param name Nome do usuário.
-- @param privateKey Chave privada.
-- @param acsCertificate Certificado a ser fornecido ao Serviço de Controle de
--        Acesso.
--
-- @return O Serviço de Registro. {@code false} caso ocorra algum erro.
--
-- @throws InvalidCredentialException Caso a credencial seja rejeitada ao
--         tentar obter o Serviço de Registro.
---
function Openbus:connectByCertificate(name, privateKeyFile, acsCertificateFile)
  if not name or not privateKeyFile or not acsCertificateFile then
    log:error("OpenBus: Nenhum parâmetro pode ser nil.")
    return false
  end
  if self.connectionState == 2 then
    if not self.acs then
      if not self:_fetchACS() then
        log:error("OpenBus: Não foi possível acessar o barramento.")
        return false
      end
    end
    local challenge = self.acs:getChallenge(name)
    if not challenge or #challenge == 0 then
      log:error("OpenBus: o desafio para " .. name ..
        " não foi obtido junto ao Servico de Controle de Acesso.")
      return false
    end
    local privateKey, err = lce.key.readprivatefrompemfile(privateKeyFile)
    if not privateKey then
      log:error("OpenBus: erro obtendo chave privada para ".. name .. " em " ..
        privateKeyFile .. ": " .. err)
      return false
    end
    local answer = lce.cipher.decrypt(privateKey, challenge)
    local certificate = lce.x509.readfromderfile(acsCertificateFile)
    answer = lce.cipher.encrypt(certificate:getpublickey(), answer)
    local success, credential, lease = self.acs:loginByCertificate(name, answer)
    if success then
      return self:_completeConnection(credential, lease)
    else
      log:error("OpenBus: Falha no login de " .. name)
      return false
    end
  else
    log:error("OpenBus: O barramento já está conectado.")
    return false
  end
end

---
-- Realiza uma tentativa de conexão com o barramento(serviço de controle de
-- acesso e o serviço de registro), a partir de uma credencial.
--
-- @param credential A credencial.
--
-- @return O serviço de registro. {@code false} caso ocorra algum erro.
--
-- @throws ACSUnavailableException Caso o Serviço de Controle de Acesso não
--         consiga ser contactado.
---
function Openbus:connectByCredential(credential)
  if not credential then
    log:error("OpenBus: O parâmetro 'credential' não pode ser nil.")
    return false
  end
  if not self.acs then
    if not self:_fetchACS() then
      log:error("OpenBus: Não foi possível acessar o barramento.")
      return false
    end
  end
  if self.acs:isValid(credential) then
    self.credentialManager:setValue(credential)
    if not self.rgs then
    	local registryService = self.acs:getRegistryService()
  			self.rgs = self.orb:narrow(registryService,
                    "IDL:openbusidl/rs/IRegistryService:1.0")
    end
    return self.rgs
  end
  log:error("OpenBus: Credencial inválida.")
  return false
end

---
-- Desfaz a conexão atual.
--
-- @return {@code true} caso a conexão seja desfeita, ou {@code false} se
--         nenhuma conexão estiver ativa ou ocorra um erro.
---
function Openbus:disconnect()
  if self.connectionState == 1 then
    if self.leaseRenewer then
      local status, err = oil.pcall(self.leaseRenewer.stopRenew,
        self.leaseRenewer)
      if not status then
        self.connectionState = 1
        log:error(
          "OpenBus: Não foi possível parar a renovação de lease. Erro: " .. err)
        return false
      end
      self.leaseRenewer = nil
    end
    status, err = oil.pcall(self.acs.logout, self.acs,
      self.credentialManager:getValue())
    if not status then
      self.connectionState = 1
      log:error("OpenBus: Não foi possível realizar o logout. Erro " .. err)
      return false
    end
    return status
  else
    return false
  end
end

function Openbus:destroy()
  self:_reset()
end

---
-- Informa o estado de conexão com o barramento.
--
-- @return {@code true} caso a conexão esteja ativa, ou {@code false}, caso
--         contrário.
---
function Openbus:isConnected()
  if self.connectionState == 1 then
    return true
  end
  return false
end

---
-- Adiciona um observador para receber eventos de expiração do <i>lease</i>.
--
-- @param lec O observador.
--
---
function Openbus:addLeaseExpiredCallback(lec)
  self.leaseExpiredCallback = lec
  if self.connectionState == 1 then
    if self.leaseRenewer then
      self.leaseRenewer:setLeaseExpiredCallback(lec)
    end
  end
end

---
-- Remove um observador de expiração do <i>lease</i>.
--
---
function Openbus:removeLeaseExpiredCallback()
  self.leaseExpiredCallback = nil
  if self.connectionState == 1 then
    if self.leaseRenewer then
      self.leaseRenewer:setLeaseExpiredCallback(nil)
    end
  end
end

---
-- Indica se o método da interface deve ser interceptado.
--
-- @param iface RepID da interface do método.
-- @param method Nome do método.
-- @param interceptable Indica se o método deve ser interceptado ou não.
--
function Openbus:setInterceptable(iface, method, interceptable)
  -- Guarda apenas os métodos que não devem ser interceptados
  local methods
  if interceptable then
    methods = self.ifaceMap[iface]
    if methods then
      methods[method] = nil
      if not next(method) then
        self.ifaceMap[iface] = nil
      end
    end
  else
    methods = self.ifaceMap[iface]
    if not methods then
      methods = {}
      self.ifaceMap[iface] = methods
    end
    methods[method] = true
  end
end

---
-- Consulta se o método deve ser interceptado.
--
-- @param iface RepID da interface do método.
-- @param method Nome do método.
--
-- @return true se o método deve ser interceptado e false, caso contrário.
--
function Openbus:isInterceptable(iface, method)
  local methods = self.ifaceMap[iface]
  return not (methods and methods[method])
end

return Openbus()
