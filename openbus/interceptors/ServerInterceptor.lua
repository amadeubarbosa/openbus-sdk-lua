-- $Id$

local print  = print
local pairs  = pairs
local ipairs = ipairs
local format = string.format

local oil = require "oil"
local orb = oil.orb

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
  local lir = orb:getLIR()
  
  -- Obtém as operações das interfaces que devem ser verificadas
  local allowedOperations
  if config.interfaces then
    allowedOperations = {}
    for _, iconfig in ipairs(config.interfaces) do
      local allowed = {}
      allowedOperations[iconfig.interface] = allowed
      Log:interceptor(true, format("Checar interface: %s", iconfig.interface))
      local excluded_ops = iconfig.excluded_ops or {}
      for _, op in ipairs(excluded_ops) do
        allowed[op] = true
        Log:interceptor(format("Não checar operação: %s", op))
      end
      Log:interceptor(false)
    end
  else
    -- Se nenhuma interface especificada, checa todas as operações
    Log:interceptor("checar todas as operações de qualquer interface")
  end

  return oop.rawnew(self, {
    allowedOperations = allowedOperations,
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
  local op = request.operation
  local allowed = self.allowedOperations and 
                  self.allowedOperations[repID] and
                  self.allowedOperations[repID][op]
  local corba = giop.ObjectOperations[op]

  if (repID == "IDL:openbusidl/acs/IAccessControlService:1.0") and
     (op == "loginByPassword")
  then
    Log:interceptor("Desligando verbose do dispatcher...")
    oil.verbose:flag("dispatcher", false)
  end

  if corba or allowed then
    Log:interceptor(format("OPERAÇÂO %s NÂO È CHECADA", op))
    return
  end
  Log:interceptor(format("OPERAÇÂO %s É CHECADA", op))

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
