-- $Id$

local oil = require "oil"
local orb = oil.orb

local oop = require "loop.base"

local log = require "openbus.common.Log"

---
--Interceptador de requisições de serviço, responsável por inserir no contexto
--da requisição a credencial do cliente.
---
module("openbus.common.ClientInterceptor", oop.class)

---
--Cria o interceptador.
--
--@param config As configurações do interceptador.
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
                     contextID = config.contextID})
end

---
--Intercepta o request para envio da informação de contexto (credencial)
--
--@param request Informações sobre a requisição.
---
function sendrequest(self, request)
  log:interceptor("INTERCEPTAÇÂO CLIENTE OP: "..request.operation)

  -- Verifica de existe credencial para envio
  if not self.credentialManager:hasValue() then
    log:interceptor "SEM CREDENCIAL !"
    return
  end
  log:interceptor("TEM CREDENCIAL!")

  -- Insere a credencial no contexto do serviço
  local encoder = orb:newencoder()
  encoder:put(self.credentialManager:getValue(), 
              self.credentialType)
  request.service_context =  {
    { context_id = self.contextID, context_data = encoder:getdata() }
  }
  log:interceptor("INSERI CREDENCIAL")
end
