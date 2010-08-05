-- $Id$

local oil = require "oil"
local orb = oil.orb

local oop = require "loop.base"

local log = require "openbus.util.Log"

---
--Interceptador de requisi��es de servi�o, respons�vel por inserir no contexto
--da requisi��o a credencial do cliente.
---
module("openbus.interceptors.ClientInterceptor", oop.class)

---
--Cria o interceptador.
--
--@param config As configura��es do interceptador.
--@param credentialManager O objeto onde a credencial do membro fica armazenada.
--
--@return O interceptador.
---
function __init(self, config, credentialManager)

  log:interceptor("Construindo interceptador para cliente")
  local lir = orb:getLIR()
  return oop.rawnew(self,
           {credentialManager = credentialManager,
            credentialType = lir:lookup_id(config.credential_type).type,
            credentialType_v1_05 = lir:lookup_id(config.credential_type_v1_05).type,
            contextID = config.contextID})
end

---
--Intercepta o request para envio da informa��o de contexto (credencial)
--
--@param request Informa��es sobre a requisi��o.
---
function sendrequest(self, request)
  log:interceptor("INTERCEPTA��O CLIENTE OP: "..request.operation_name)
  -- Verifica de existe credencial para envio
  if not self.credentialManager:hasValue() then
    log:interceptor "SEM CREDENCIAL !"
    return
  end
  log:interceptor("TEM CREDENCIAL!")

  -- Insere a credencial no contexto do servi�o
  local encoder = orb:newencoder()
  encoder:put(self.credentialManager:getValue(),
              self.credentialType)
  encoder:put(self.credentialManager:getValue(),
              self.credentialType_v1_05)
  request.service_context =  {
    { context_id = self.contextID, context_data = encoder:getdata() }
  }
  log:interceptor("INSERI CREDENCIAL")
end
