-- $Id$

local print  = print
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
  Log:interceptor("Construindo interceptador para servi�o")
  local lir = Openbus:getORB():getLIR()
  -- Obt�m as opera��es das interfaces que devem ser verificadas
  if config.interfaces then
    for _, iconfig in ipairs(config.interfaces) do
      Log:interceptor(true, format("Checar interface: %s", iconfig.interface))
      for _, op in ipairs(iconfig.excluded_ops or {}) do
        Openbus:setInterceptable(iconfig.interface, op, false)
        Log:interceptor(format("N�o checar opera��o: %s", op))
      end
      Log:interceptor(false)
    end
  else
    -- Se nenhuma interface especificada, checa todas as opera��es
    Log:interceptor("checar todas as opera��es de qualquer interface")
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
  end
  local obj = oop.rawnew(self, {
    credentialType = lir:lookup_id(config.credential_type).type,
    credentialType_v1_05 = lir:lookup_id(config.credential_type_v1_05).type,
    contextID = config.contextID,
    picurrent = PICurrent(),
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
    Log:interceptor("Cache de credenciais com capacidade m�xima de " ..
      MAXIMUM_CREDENTIALS_CACHE_SIZE .. " credenciais.");
    Log:interceptor("Revalida��o do cache realizada a cada " ..
      TASK_DELAY .. " segundos.");
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

  request.requeststart = socket.gettime()
  if self.tests[request.object_key] ~= nil then
       self.tests[request.object_key]:receiverequest("; inicio; 0;"..
                         request.object_key .. "; " ..
                         request.operation_name .. "-" .. request.requeststart)
  end

  Log:interceptor "INTERCEPTA��O SERVIDOR!"

  local repID = request.interface.repID
  request.repID = repID
  local allowed = not (Openbus:isInterceptable(repID, request.operation_name) and
    Openbus:isInterceptable("::CORBA::Object", request.operation_name))

  if ( (repID == Utils.ACCESS_CONTROL_SERVICE_INTERFACE) or
       (repID == Utils.ACCESS_CONTROL_SERVICE_INTERFACE_V1_04) ) and
     (request.operation_name == "loginByPassword")
  then
    Log:interceptor("Desligando verbose do dispatcher...")
    oil.verbose:flag("dispatcher", false)
  end

  local oldPolicy = self.policy
  if ( (repID == Utils.ACCESS_CONTROL_SERVICE_INTERFACE) or
       (repID == Utils.ACCESS_CONTROL_SERVICE_INTERFACE_V1_04) ) and
     (request.operation_name == "loginByCertificate")
  then
    --for�a a inserir credencial, ACSs nao podem se logar sem passar suas credenciais
    allowed = false
    self.policy = Utils.CredentialValidationPolicy[3]
  end

  if allowed then
    Log:interceptor(format("OPERA��O %s N�O � CHECADA", request.operation_name))

    if self.tests[request.object_key] ~= nil then
       self.tests[request.object_key]:receiverequest("; fim    ; "  .. socket.gettime() - request.requeststart .. "; "..
                           request.object_key .. "; " .. request.operation_name.. "-" .. request.requeststart)
    end
    return
  else
    Log:interceptor(format("OPERA��O %s � CHECADA", request.operation_name))
    local credential, credential_v1_05
    for _, context in ipairs(request.service_context) do
      if context.context_id == self.contextID then
        Log:interceptor "TEM CREDENCIAL!"
        local decoder = orb:newdecoder(context.context_data)
        local status, cred = oil.pcall(decoder.get, decoder, self.credentialType)
        if status then
          credential = cred
          Log:interceptor(format("CREDENCIAL V1.04: %s, %s", credential.identifier,
            credential.owner))
        end
        status, cred = oil.pcall(decoder.get, decoder, self.credentialType_v1_05)
        if status then
          credential_v1_05 = cred
          Log:interceptor(format("CREDENCIAL V1.05: %s, %s", credential_v1_05.identifier,
            credential_v1_05.owner))
        end
        break
      end
    end
    local credentialFound = credential_v1_05 or credential

    -- trata politica
    if self.policy == Utils.CredentialValidationPolicy[3] then
      -- politica sem validacao
      Log:interceptor("Utilizando pol�tica sem valida��o de credencial. A credencial n�o ser� checada.")
      self.picurrent:setValue(credentialFound)
      if self.tests[request.object_key] ~= nil then
               self.tests[request.object_key]:receiverequest("; fim    ; "
                           .. socket.gettime() - request.requeststart .. "; "..
                           request.object_key .. "; " .. request.operation_name.. "-" .. request.requeststart)
      end
      self.policy = oldPolicy
      return
    end
    if self.policy == Utils.CredentialValidationPolicy[2] then
      -- politica de cache
      self:lock(request)
      for i, v in ipairs(self.credentials) do
        if (credential_v1_05 and self:areCredentialsEqual(credential_v1_05, v)) or
           (credential and self:areCredentialsEqual(credential, v))
        then
          Log:interceptor("A credencial interceptada est� na cache.")
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
      Log:interceptor("A credencial interceptada n�o est� na cache.")
      if self:isValid(credential_v1_05, credential, request) then
        Log:interceptor("A credencial interceptada � v�lida.")
        self:lock(request)
        if #self.credentials == MAXIMUM_CREDENTIALS_CACHE_SIZE then
          Log:interceptor("A cache est� cheia.")
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
      if self:isValid(credential_v1_05, credential, request) then
        if self.tests[request.object_key] ~= nil then
               self.tests[request.object_key]:receiverequest("; fim    ; "
                           .. socket.gettime() - request.requeststart .. "; "..
                           request.object_key .. "; " .. request.operation_name.. "-" .. request.requeststart)
        end
        return
      end
    end

    -- Credencial inv�lida ou sem credencial
    if credentialFound then
      Log:interceptor("\n ***CREDENCIAL INVALIDA ***\n")
    else
      Log:interceptor("\n***N�O TEM CREDENCIAL ***\n")
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
  if self.tests[request.object_key] ~= nil then
       self.tests[request.object_key]:sendreply("; inicio; " ..
                           socket.gettime() - request.requeststart .. "; "..
                           request.object_key .. "; " .. request.operation_name.. "-" .. request.requeststart)
  end

  if (request.operation_name == "loginByPassword") then
    Log:interceptor("Ligando verbose do dispatcher...")
    oil.verbose:flag("dispatcher", true)
  end
  request.service_context = {}

  if self:needUpdate(request) then
    local key = request.object_key
    Log:interceptor("Atualizando estado para operacao: [".. request.operation_name .."].")
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
end

---
--Obt�m a credencial da entidade que est� realizando uma requisi��o.
--
--@return A credencial da entidade.
---
function getCredential(self)
  return self.picurrent:getValue()
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
      Log:interceptor(format("CREDENCIAL VALIDADA PARA %s", request.operation_name))
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
    Log:interceptor("ATEN��O: Impossivel verificar as credenciais da cache por estar travada. Tentando novamente.")
  end
  if #self.obj.credentials > 0 then
    Log:interceptor("Executando a valida��o de credenciais.")
    local success, results = oil.pcall(self.obj.accessControlService.areValid,
      self.obj.accessControlService, self.obj.credentials)
    if success then
      local shift = 0
      for i, ret in ipairs(results) do
        if not ret then
          Log:interceptor("A credencial " .. i .. " n�o � mais v�lida.")
          table.remove(self.obj.credentials, i - shift)
          shift = shift + 1
        else
          Log:interceptor("A credencial " .. i .. " ainda � v�lida.")
        end
      end
    else
      Log:interceptor("Erro ao tentar validar as credenciais:\n" .. results)
    end
  else
    Log:interceptor("Valida��o de credenciais n�o foi executada pois n�o existem credenciais na cache.")
  end
  self.obj:unlock()
end

---
-- Tenta validar as credenciais de duas versoes do barramento.
---
function isValid(self, credential, prev, request)
  if (credential and self:validateCredential(credential, request)) or
     (prev and self:validateCredential(prev, request)) then
    return true
  end
  return false
end

---
-- Trava a tabela de credenciais.
---
function lock(self, request)
  local numWaits = 1
  local maxWaits = 10
  while numWaits <= maxWaits do
    if self.myLock then
      Log:interceptor("Lista de credenciais travada. Aguardando meio segundo para tentar novamente e dar prosseguimento � chamada.")
      oil.sleep(0.5)
      numWaits = numWaits + 1
    else
      break
    end
  end
  if numWaits > maxWaits then
    Log:interceptor("Lista de credenciais travada por mais de 5 segundos, abortando opera��o.")
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
