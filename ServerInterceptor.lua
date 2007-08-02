-----------------------------------------------------------------------------
-- Interceptador de requisi��es de servi�o, respons�vel por verificar se
--  o emissor da requisi��o foi autenticado (possui uma credencial v�lida)
--
-- �ltima altera��o:
--   $Id$
-----------------------------------------------------------------------------
local print = print
local pairs = pairs
local ipairs = ipairs

local oil = require "oil"

local Log = require "openbus.common.Log" 

local oop = require "loop.base"
module("openbus.common.ServerInterceptor", oop.class)

-- Constr�i o interceptador
function __init(self, config, picurrent, accessControlService)
  Log:interceptor("Construindo interceptador para servi�o")
  local lir = oil.getLIR()

  -- Obt�m as opera��es das interfaces que devem ser verificadas
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
          Log:interceptor("checar opera��o: "..op)
        end
      end
      Log:interceptor(false)
    end
  else
    -- Se nenhuma interface especificada, checa todas as opera��es
    checkedOperations.all = true
    Log:interceptor("checar todas as opera��es de qualquer interface")
  end

  return oop.rawnew(self, 
                    { checkedOperations = checkedOperations,
                      credentialType = lir:lookup_id(config.credential_type).type,
                      contextID = config.contextID,
                      picurrent = picurrent,
                      accessControlService = accessControlService })
end

-- Intercepta o request para obten��o da informa��o de contexto (credencial)
function receiverequest(self, request)
  Log:interceptor "INTERCEPTA��O SERVIDOR!"

  if not (self.checkedOperations.all or 
          self.checkedOperations[request.operation]) then
    Log:interceptor ("OPERA��O "..request.operation.." N�O � CHECADA")
    return
  end
  Log:interceptor ("OPERA��O "..request.operation.." � CHECADA")

  local credential
  for _, context in ipairs(request.service_context) do
    if context.context_id == self.contextID then
      Log:interceptor "TEM CREDENCIAL!"
      local decoder = oil.newdecoder(context.context_data)
      credential = decoder:get(self.credentialType)
      Log:interceptor("CREDENCIAL: "..credential.identifier..","..credential.entityName)
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

  -- Credencial inv�lida ou sem credencial
  if credential then
    Log:interceptor("\n ***CREDENCIAL INVALIDA ***\n")
  else
    Log:interceptor("\n***N�O TEM CREDENCIAL ***\n")
  end
  request.success = false
  request.count = 1
  request[1] = oil.newexcept{"CORBA::NO_PERMISSION", minor_code_value = 0}
end

--
-- Intercepta a resposta ao request para "limpar" o contexto
--
function sendreply(self, request)
  request.service_context = {}
end
