-- $Id$

local print = print
local pairs = pairs
local ipairs = ipairs

local oil = require "oil"
local orb = oil.orb

local Log = require "openbus.common.Log"
local PICurrent = require "openbus.common.PICurrent"

local oop = require "loop.base"

---
--Interceptador de requisições de serviço, responsável por verificar se o
--emissor da requisição foi autenticado (possui uma credencial válida).
---
module("openbus.common.ServerInterceptor", oop.class)

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
  local checkedOperations = {}
  if config.interfaces then
    for _, iconfig in ipairs(config.interfaces) do
      local iface = lir:resolve(iconfig.interface)
      Log:interceptor(true, "checar interface: "..iconfig.interface)
      local excluded_ops = iconfig.excluded_ops or {}
      for _, member in ipairs(iface.definitions) do
        local op = member.name
        if member._type == "operation" and not excluded_ops[op] then
          checkedOperations[op] = true
          Log:interceptor("checar operação: "..op)
        end
      end
      Log:interceptor(false)
    end
  else
    -- Se nenhuma interface especificada, checa todas as operações
    checkedOperations.all = true
    Log:interceptor("checar todas as operações de qualquer interface")
  end

  return oop.rawnew(self,
                    { checkedOperations = checkedOperations,
                      credentialType = lir:lookup_id(config.credential_type).type,
                      contextID = config.contextID,
                      picurrent = PICurrent(),
                      accessControlService = accessControlService })
end

---
--Intercepta o request para obtenção da informação de contexto (credencial).
--
--@param request Dados sobre o request.
---
function receiverequest(self, request)
  Log:interceptor "INTERCEPTAÇÂO SERVIDOR!"

  if (request.operation == "loginByPassword") then
    Log:interceptor("Desligando verbose do dispatcher...")
    oil.verbose:flag("dispatcher", false)
  end

  if not (self.checkedOperations.all or
          self.checkedOperations[request.operation]) then
    Log:interceptor ("OPERAÇÂO "..request.operation.." NÂO È CHECADA")
    return
  end
  Log:interceptor ("OPERAÇÂO "..request.operation.." É CHECADA")

  local credential
  for _, context in ipairs(request.service_context) do
    if context.context_id == self.contextID then
      Log:interceptor "TEM CREDENCIAL!"
      local decoder = orb:newdecoder(context.context_data)
      credential = decoder:get(self.credentialType)
      Log:interceptor("CREDENCIAL: "..credential.identifier..","..credential.owner)
      break
    end
  end

  if credential then
    local success, res = oil.pcall(self.accessControlService.isValid,
                                   self.accessControlService, credential)
    if success and res then
      Log:interceptor("CREDENCIAL VALIDADA PARA "..request.operation)
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
