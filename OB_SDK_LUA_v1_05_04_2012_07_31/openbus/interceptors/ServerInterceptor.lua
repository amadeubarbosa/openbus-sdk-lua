-- $Id$

local pairs  = pairs
local ipairs = ipairs
local format = string.format
local coroutine = coroutine
local os = os
local table = table

local socket = require "socket"
local oil = require "oil"
local orb = oil.orb

local Openbus   = require "openbus.Openbus"
local Log       = require "openbus.util.Log"
local PICurrent = require "openbus.interceptors.PICurrent"
local ServiceStatusManager = require "openbus.faulttolerance.ServiceStatusManager"
local Utils     = require "openbus.util.Utils"

local oop   = require "loop.base"
local giop  = require "oil.corba.giop"
local Timer = require "loop.thread.Timer"


---
--Interceptador de requisi��es de servi�o, respons�vel por verificar se o
--emissor da requisi��o foi autenticado (possui uma credencial v�lida).
---
module("openbus.interceptors.ServerInterceptor", oop.class)

---
-- Intervalo de tempo para execucao da tarefa de validacao das credenciais da cache.
---
TASK_DELAY = 5 * 60 -- 5 minutos

---
-- Tamanho maximo do cache de credenciais.
---
MAXIMUM_CREDENTIALS_CACHE_SIZE = 20

---
--Constr�i o interceptador.
--
--@param config As configura��es do interceptador.
--@param accessControlService O servi�o de controle de acesso.
--
--@return O interceptador.
---
function __init(self, config, accessControlService, policy)
  Log:debug("Construindo o interceptador de servidor")
  -- Obt�m as opera��es das interfaces que devem ser verificadas
  if config.interfaces then
    for _, iconfig in ipairs(config.interfaces) do
      Log:config(format("A interface %s ser� interceptada",
          iconfig.interface))
      for _, op in ipairs(iconfig.excluded_ops or {}) do
        Openbus:setInterceptable(iconfig.interface, op, false)
        Log:config(format("A opera��o %s da interface %s n�o ser� interceptada",
            op, iconfig.interface))
      end
    end
  else
    -- Se nenhuma interface especificada, checa todas as opera��es
    Log:config("Todas  as opera��es de todas as interfaces ser�o interceptadas")
  end
  local updateOperations = {}
  if config.ft_update_policy then
     for _, iconfig in ipairs(config.ft_update_policy) do
        for _, op in ipairs(iconfig.update_ops or {}) do
          if not updateOperations[iconfig.interface] then
            updateOperations[iconfig.interface] = {}
          end
          updateOperations[iconfig.interface][op] = true
        end
    end
  end

  -- Adiciona as opera��es de CORBA como n�o verificadas.
  -- A classe Object de CORBA n�o tem repID, criar um identificar interno.
  for op in pairs(giop.ObjectOperations) do
    Openbus:setInterceptable("::CORBA::Object", op, false)
    Log:interceptor(format("N�o checar opera��o: %s", op))
  end

  local obj = oop.rawnew(self, {
    configCredentialType = config.credential_type,
    configCredentialTypePrev = config.credential_type_prev,
    contextID = config.contextID,
    picurrent = PICurrent(),
    isOiLVerboseDispatcherEnabled = oil.verbose:flag("dispatcher"),
    accessControlService = accessControlService,
    tests = config.tests or {},
    policy = policy,
    updateOperations = updateOperations,
    updateThreads = {},
    serviceStatusManager = ServiceStatusManager:__init(),
  })

  -- Cria o timer caso a politica seja cached
  if policy == Utils.CredentialValidationPolicy[2] then
    obj.credentials = {}
    obj.myLock = false
    obj.myTimer = Timer()
    obj.myTimer.obj = obj
    obj.myTimer.scheduler = oil.tasks
    obj.myTimer.rate = TASK_DELAY
    obj.myTimer.action = credentialValidatorAction
    obj.myTimer:enable()
    Log:config(format("Utilizando cache com capacidade m�xima de %d credenciais",
        MAXIMUM_CREDENTIALS_CACHE_SIZE))
    Log:config(format("A cache de credenciais ser� atualizada a cada %d segundos",
        TASK_DELAY))
  end
  return obj
end

---
--Intercepta o request para obten��o da informa��o de contexto (credencial).
--
--@param request Dados sobre o request.
---
function receiverequest(self, request)
  -- Caso o objeto n�o exista, deixar o OiL lan�ar exce��o OBJECT_NOT_EXIST
  if not request.servant then
    return
  end

  local lir = Openbus:getORB():getLIR()
  if not self.credentialType then
   self.credentialType = lir:lookup_id(self.configCredentialType).type
   self.credentialTypePrev = lir:lookup_id(self.configCredentialTypePrev).type
  end

  request.requeststart = socket.gettime()
  if self.tests[request.object_key] ~= nil then
       self.tests[request.object_key]:receiverequest("; inicio; 0;"..
                         request.object_key .. "; " ..
                         request.operation_name .. "-" .. request.requeststart)
  end

  local repID = request.interface.repID
  request.repID = repID
  local allowed = not (Openbus:isInterceptable(repID, request.operation_name) and
    Openbus:isInterceptable("::CORBA::Object", request.operation_name))

  if ((repID == Utils.ACCESS_CONTROL_SERVICE_INTERFACE) or
      (repID == Utils.ACCESS_CONTROL_SERVICE_INTERFACE_PREV) ) and
      (request.operation_name == "loginByPassword") and
      self.isOiLVerboseDispatcherEnabled
  then
    Log:debug("Desativando o verbose do dispatcher")
    oil.verbose:flag("dispatcher", false)
  end

  local oldPolicy = self.policy
  if ( (repID == Utils.ACCESS_CONTROL_SERVICE_INTERFACE) or
       (repID == Utils.ACCESS_CONTROL_SERVICE_INTERFACE_PREV) ) and
     (request.operation_name == "loginByCertificate")
  then
    --for�a a inserir credencial, ACSs nao podem se logar sem passar suas credenciais
    allowed = false
    self.policy = Utils.CredentialValidationPolicy[3]
  end

  if allowed then
    Log:debug(format("A opera��o %s n�o deve ser interceptada",
        request.operation_name))

    if self.tests[request.object_key] ~= nil then
       self.tests[request.object_key]:receiverequest("; fim    ; "  .. socket.gettime() - request.requeststart .. "; "..
                           request.object_key .. "; " .. request.operation_name.. "-" .. request.requeststart)
    end
    return
  else
    Log:debug(format("A opera��o %s foi interceptada", request.operation_name))
    local credential, credentialPrev
    for _, context in ipairs(request.service_context) do
      if context.context_id == self.contextID then
        local decoder = orb:newdecoder(context.context_data)
        local status, cred = oil.pcall(decoder.get, decoder, self.credentialType)
        if status then
          credential = cred
          Log:debug(format(
              "A credencial {%s, %s, %s} de tipo %s foi recebida",
              credential.identifier, credential.owner, credential.delegate,
              self.credentialType.repID))
          if self:checkSameProcess(request, credential) then
            return
          end
        end
        status, cred = oil.pcall(decoder.get, decoder, self.credentialTypePrev)
        if status then
          credentialPrev = cred
          Log:debug(format(
              "A credencial {%s, %s, %s} de tipo %s foi recebida",
              credentialPrev.identifier, credentialPrev.owner,
              credentialPrev.delegate, self.credentialTypePrev.repID))
          if self:checkSameProcess(request, credential_v1_05) then
            return
          end
        end
        break
      end
    end
    local credentialFound = credentialPrev or credential

    -- trata politica
    if self.policy == Utils.CredentialValidationPolicy[3] then
      -- politica sem validacao
      Log:debug("Utilizando pol�tica sem valida��o de credencial. A credencial n�o ser� checada.")
      self.picurrent:setValue(credentialFound)
      if self.tests[request.object_key] ~= nil then
               self.tests[request.object_key]:receiverequest("; fim    ; "
                           .. socket.gettime() - request.requeststart .. "; "..
                           request.object_key .. "; " .. request.operation_name.. "-" .. request.requeststart)
      end
      self.policy = oldPolicy
      return
    end

    if credentialFound then
      if self.policy == Utils.CredentialValidationPolicy[2] then
        -- politica de cache
        self:lock(request)
        for i, v in ipairs(self.credentials) do
          if (credentialFound and self:areCredentialsEqual(credentialFound, v))
          then
            Log:debug(format("A credencial {%s, %s, %s} j� est� na cache",
                credentialFound.identifier, credentialFound.owner,
                credentialFound.delegate))
            table.remove(self.credentials, i)
            table.insert(self.credentials, credentialFound)
            self.picurrent:setValue(credentialFound)
            self:unlock()
            if self.tests[request.object_key] ~= nil then
                 self.tests[request.object_key]:receiverequest("; fim    ; "
                             .. socket.gettime() - request.requeststart .. "; "..
                             request.object_key .. "; " .. request.operation_name.. "-" .. request.requeststart)
            end
            return
          end
        end
        self:unlock()
        Log:debug(format("A credencial {%s, %s, %s} n�o est� na cache",
            credentialFound.identifier, credentialFound.owner, credential.delegate))
        if self:validateCredential(credentialFound, request) then
          Log:debug(format("A credencial {%s, %s, %s} � v�lida",
              credentialFound.identifier, credentialFound.owner,
              credentialFound.delegate))
          self:lock(request)
          if #self.credentials == MAXIMUM_CREDENTIALS_CACHE_SIZE then
            Log:debug("A cache est� cheia.")
            table.remove(self.credentials, 1)
          end
          table.insert(self.credentials, credentialFound)
          self:unlock()
          if self.tests[request.object_key] ~= nil then
            self.tests[request.object_key]:receiverequest("; fim    ; "
                      .. socket.gettime() - request.requeststart .. "; "..
                      request.object_key .. "; " .. request.operation_name.. "-" .. request.requeststart)
          end
          return
        end
      else
        -- politica sempre
        if self:validateCredential(credentialFound, request) then
          if self.tests[request.object_key] ~= nil then
            self.tests[request.object_key]:receiverequest("; fim    ; "
                      .. socket.gettime() - request.requeststart .. "; "..
                      request.object_key .. "; " .. request.operation_name.. "-" .. request.requeststart)
          end
          return
        end
      end

      -- Credencial inv�lida ou sem credencial
      Log:debug(format("A credencial {%s, %s, %s} � inv�lida",
          credentialFound.identifier, credential.owner, credential.delegate))
    else
      Log:error(format("A opera��o %s n�o recebeu uma credencial",
          request.operation_name))
    end

    request.success = false
    request.results = { orb:newexcept{"CORBA::NO_PERMISSION", minor_code_value = 0} }

    if self.tests[request.object_key] ~= nil then
       self.tests[request.object_key]:receiverequest("; fim    ; "
                        .. socket.gettime() - request.requeststart .. "; "..
                           request.object_key .. "; " .. request.operation_name.. "-" .. request.requeststart)
    end
  end
end

---
--Intercepta a resposta ao request para "limpar" o contexto.
--
--@param request Dados sobre o request.
---
function sendreply(self, request)
  if not request.servant then
    return
  end

  if self.tests[request.object_key] ~= nil then
       self.tests[request.object_key]:sendreply("; inicio; " ..
                           socket.gettime() - request.requeststart .. "; "..
                           request.object_key .. "; " .. request.operation_name.. "-" .. request.requeststart)
  end

  local repID = request.interface.repID
  if ((repID == Utils.ACCESS_CONTROL_SERVICE_INTERFACE) or
      (repID == Utils.ACCESS_CONTROL_SERVICE_INTERFACE_V1_04) ) and
      (request.operation_name == "loginByPassword") and
      self.isOiLVerboseDispatcherEnabled
  then
    Log:debug("Reativando o verbose do dispatcher")
    oil.verbose:flag("dispatcher", true)
  end

  request.service_context = {}

  if self:needUpdate(request) then
    local key = request.object_key
    Log:debug("Atualizando estado para operacao: [".. request.operation_name ..
        "]")
    local currUpdateThread = function()
                               self.serviceStatusManager:updateStatus(key)
                             end
    local thread = coroutine.create(currUpdateThread)
    self.updateThreads[#self.updateThreads+1] = thread
    oil.tasks:resume(thread)
  end

  if self.tests[request.object_key] ~= nil then
       self.tests[request.object_key]:sendreply("; fim; "  ..
                           socket.gettime() - request.requeststart .. "; "..
                           request.object_key .. "; " .. request.operation_name.. "-" .. request.requeststart)
  end

  Log:debug(format("O reply para a opera��o %s foi enviado",
      request.operation_name))
end

---
--Obt�m a credencial da entidade que est� realizando uma requisi��o.
--
--@return A credencial da entidade.
---
function getCredential(self)
  return self.picurrent:getValue()
end

function checkSameProcess(self, request, credential)
  return false
end

function needUpdate(self, request)
   if self.updateOperations[request.repID] then
      if self.updateOperations[request.repID][request.operation_name] then
        return true
      end
   end
   return false
end

function validateCredential (self, credential, request)
  local success, res = oil.pcall(self.accessControlService.isValid,
                                 self.accessControlService, credential)
  if success and res then
    if request then
      self.picurrent:setValue(credential)
    end
    return true
  end
  return false
end

---
-- Funcao executada pelo timer para validacao das credenciais armazenadas em uma cache.
---
function credentialValidatorAction(self)
  while not self.obj:lock() do
    Log:debug("N�o foi poss�vel obter acesso exclusivo � cache de credenciais")
  end
  if #self.obj.credentials > 0 then
    Log:debug("Executando a valida��o de credenciais")
    local success, results = oil.pcall(self.obj.accessControlService.areValid,
      self.obj.accessControlService, self.obj.credentials)
    if success then
      local shift = 0
      for i, ret in ipairs(results) do
        if not ret then
          local credential = self.obj.credentials[i - shift]
          Log:debug(format("A credencial {%s, %s, %s} n�o � mais v�lida",
              credential.identifier, credential.owner, credential.delegate))
          table.remove(self.obj.credentials, i - shift)
          shift = shift + 1
        else
          local credential = self.obj.credentials[i - shift]
          Log:debug(format("A credencial {%s, %s, %s} ainda � v�lida",
              credential.identifier, credential.owner, credential.delegate))
        end
      end
    else
      Log:warn("N�o foi poss�vel validar as credenciais da cache", results)
    end
  else
    Log:debug("A valida��o de credenciais n�o foi executada pois n�o existem credenciais na cache.")
  end
  self.obj:unlock()
end

---
-- Trava a tabela de credenciais.
---
function lock(self, request)
  local numWaits = 1
  local maxWaits = 10
  while numWaits <= maxWaits do
    if self.myLock then
      Log:debug("A cache de credenciais est� em uso exclusivo no momento. Aguardando meio segundo para tentar um novo acesso exclusivo")
      oil.sleep(0.5)
      numWaits = numWaits + 1
    else
      break
    end
  end
  if numWaits > maxWaits then
    Log:debug("A cache de credenciais est� em uso exclusivo por mais de 5 segundos. A tentativa de novo acesso exclusivo � cache ser� cancelada")
    if request then
      request.success = false
      request.results = { orb:newexcept{"CORBA::TIMEOUT"} }
      return false
    end
    return false
  end
  self.myLock = true
  return true
end

---
-- Destrava a tabela de credenciais.
---
function unlock(self)
  self.myLock = false
end
---
-- Testa se duas credenciais sao iguais.
---
function areCredentialsEqual(self, c1, c2)
  if c1.identifier ~= c2.identifier then
    return false
  end
  if c1.owner ~= c2.owner then
    return false
  end
  if c1.delegate ~= c2.delegate then
    return false
  end
  return true
end
