-- $Id$

local print  = print
local pairs  = pairs
local ipairs = ipairs
local format = string.format

local oil = require "oil"
local orb = oil.orb

local Openbus   = require "openbus.Openbus"
local Log       = require "openbus.util.Log"
local PICurrent = require "openbus.interceptors.PICurrent"

local oop  = require "loop.base"
local giop = require "oil.corba.giop"

---
--Interceptador de requisições de serviço, responsável por verificar se o
--emissor da requisição foi autenticado (possui uma credencial válida).
---
module("openbus.interceptors.ServerInterceptor", oop.class)

---
--Constrói o interceptador.
--
--@param config As configurações do interceptador.
--@param accessControlService O serviço de controle de acesso.
--
--@return O interceptador.
---
function __init(self, config, accessControlService)
  Log:interceptor("Construindo interceptador para serviço")
  local lir = Openbus:getORB():getLIR()
  
  -- Obtém as operações das interfaces que devem ser verificadas
  if config.interfaces then
    for _, iconfig in ipairs(config.interfaces) do
      Log:interceptor(true, format("Checar interface: %s", iconfig.interface))
      for _, op in ipairs(iconfig.excluded_ops or {}) do
        Openbus:setInterceptable(iconfig.interface, op, false)
        Log:interceptor(format("Não checar operação: %s", op))
      end
      Log:interceptor(false)
    end
  else
    -- Se nenhuma interface especificada, checa todas as operações
    Log:interceptor("checar todas as operações de qualquer interface")
  end

  -- Adiciona as operações de CORBA como não verificadas.
  -- A classe Object de CORBA não tem repID, criar um identificar interno.
  for op in pairs(giop.ObjectOperations) do
    Openbus:setInterceptable("::CORBA::Object", op, false)
  end

  return oop.rawnew(self, {
    credentialType = lir:lookup_id(config.credential_type).type,
    contextID = config.contextID,
    picurrent = PICurrent(),
    accessControlService = accessControlService
  })
end

---
--Intercepta o request para obtenção da informação de contexto (credencial).
--
--@param request Dados sobre o request.
---
function receiverequest(self, request)
  Log:interceptor "INTERCEPTAÇÂO SERVIDOR!"

  -- XXX: nao existe forma padrao de recuperar o repID, esta e' uma
  -- intrusao no OiL, ou seja, pode quebrar no futuro.
  local repID = orb.ServantIndexer.indexer:typeof(request.object_key).repID
  local allowed = not (Openbus:isInterceptable(repID, request.operation) and
    Openbus:isInterceptable("::CORBA::Object", request.operation))

  if (repID == "IDL:openbusidl/acs/IAccessControlService:1.0") and
     (request.operation == "loginByPassword")
  then
    Log:interceptor("Desligando verbose do dispatcher...")
    oil.verbose:flag("dispatcher", false)
  end

  if allowed then
    Log:interceptor(format("OPERAÇÂO %s NÂO È CHECADA", request.operation))
    return
  end
  Log:interceptor(format("OPERAÇÂO %s É CHECADA", request.operation))

  local credential
  for _, context in ipairs(request.service_context) do
    if context.context_id == self.contextID then
      Log:interceptor "TEM CREDENCIAL!"
      local decoder = orb:newdecoder(context.context_data)
      credential = decoder:get(self.credentialType)
      Log:interceptor(format("CREDENCIAL: %s, %s", credential.identifier,
         credential.owner))
      break
    end
  end

  if credential then
    local success, res = oil.pcall(self.accessControlService.isValid,
                                   self.accessControlService, credential)
    if success and res then
      Log:interceptor(format("CREDENCIAL VALIDADA PARA %s", request.operation))
      self.picurrent:setValue(credential)
      return
    end
  end

  -- Credencial inválida ou sem credencial
  if credential then
    Log:interceptor("\n ***CREDENCIAL INVALIDA ***\n")
  else
    Log:interceptor("\n***NÂO TEM CREDENCIAL ***\n")
  end
  request.success = false
  request.count = 1
  request[1] = orb:newexcept{"CORBA::NO_PERMISSION", minor_code_value = 0}
end

---
--Intercepta a resposta ao request para "limpar" o contexto.
--
--@param request Dados sobre o request.
---
function sendreply(self, request)
  if (request.operation == "loginByPassword") then
    Log:interceptor("Ligando verbose do dispatcher...")
    oil.verbose:flag("dispatcher", true)
  end
  request.service_context = {}
end

---
--Obtém a credencial da entidade que está realizando uma requisição.
--
--@return A credencial da entidade.
---
function getCredential(self)
  return self.picurrent:getValue()
end
