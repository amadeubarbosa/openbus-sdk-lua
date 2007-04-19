-----------------------------------------------------------------------------
-- Interceptador de requisições de serviço, responsável por verificar se
--  o emissor da requisição foi autenticado (possui uma credencial válida)
--
-- Última alteração:
--   $Id$
-----------------------------------------------------------------------------
local oil = require "oil"
local oop = require "loop.base"

local log = require "openbus.common.Log" 

local pairs = pairs
local ipairs = ipairs

module("openbus.common.ServerInterceptor", oop.class)

-- Constrói o interceptador
function __init(self, config, picurrent, accessControlService)
  log:interceptor("Construindo interceptador para serviço")
  local lir = oil.getLIR()

  -- Obtém as operações das interfaces que devem ser verificadas
  local checkedOperations = {}
  if config.interfaces then
    for _, iconfig in ipairs(config.interfaces) do
      local iface = lir:resolve(iconfig.interface)
      log:interceptor(true, "checar interface: "..iconfig.interface)
      local excluded_ops = iconfig.excluded_ops or {}
      for _, member in ipairs(iface.definitions) do
        local op = member.name
        if member._type == "operation" and not excluded_ops[op] then
          checkedOperations[op] = true
          log:interceptor("checar operação: "..op)
        end
      end
      log:interceptor(false)
    end
  else
    -- Se nenhuma interface especificada, checa todas as operações
    checkedOperations.all = true
    log:interceptor("checar todas as operações de qualquer interface")
  end

  return oop.rawnew(self, 
                    { checkedOperations = checkedOperations,
                      credentialType = lir:lookup_id(config.credential_type).type,
                      contextID = config.contextID,
                      picurrent = picurrent,
                      accessControlService = accessControlService })
end

-- Intercepta o request para obtenção da informação de contexto (credencial)
function receiverequest(self, request)
  log:interceptor "INTERCEPTAÇÂO SERVIDOR!"

  if not (self.checkedOperations.all or 
          self.checkedOperations[request.operation]) then
    log:interceptor ("OPERAÇÂO "..request.operation.." NÂO È CHECADA")
    return
  end
  log:interceptor ("OPERAÇÂO "..request.operation.." É CHECADA")

  local credential
  for _, context in ipairs(request.service_context) do
    if context.context_id == self.contextID then
      log:interceptor "TEM CREDENCIAL!"
      local decoder = oil.newdecoder(context.context_data)
      credential = decoder:get(self.credentialType)
      log:interceptor("CREDENCIAL: "..credential.identifier..","..credential.entityName)
      break
    end
  end

  if credential and self.accessControlService:isValid(credential) then
      log:interceptor("CREDENCIAL VALIDADA PARA "..request.operation)
      self.picurrent:setValue(credential)
      return
  end

  -- Credencial inválida ou sem credencial
  if credential then
    log:interceptor("\n ***CREDENCIAL INVALIDA ***\n")
  else
    log:interceptor("\n***NÂO TEM CREDENCIAL ***\n")
  end
  request.success = false
  request.count = 1
  request[1] = oil.newexcept{"NO_PERMISSION", minor_code_value = 0}
end

--
-- Intercepta a resposta ao request para "limpar" o contexto
--
function sendreply(self, request)
  request.service_context = {}
end
