-- $Id$

local format = string.format

local oil = require "oil"
local orb = oil.orb

local oop = require "loop.base"

local Log = require "openbus.util.Log"

---
--Interceptador de requisições de serviço, responsável por inserir no contexto
--da requisição a credencial do cliente.
---
module("openbus.interceptors.ClientInterceptor", oop.class)

---
--Cria o interceptador.
--
--@param config As configurações do interceptador.
--@param credentialManager O objeto onde a credencial do membro fica armazenada.
--
--@return O interceptador.
---
function __init(self, config, credentialManager)
  Log:debug("Construindo o interceptador de cliente")
  local lir = orb:getLIR()
  return oop.rawnew(self,
           {credentialManager = credentialManager,
            credentialType = lir:lookup_id(config.credential_type).type,
            credentialTypePrev = lir:lookup_id(config.credential_type_prev).type,
            contextID = config.contextID})
end

---
--Intercepta o request para envio da informação de contexto (credencial)
--
--@param request Informações sobre a requisição.
---
function sendrequest(self, request)
  -- Verifica de existe credencial para envio
  if not self.credentialManager:hasValue() then
    Log:debug(format("Não há credencial para enviar à operação %s",
        request.operation_name))
    return
  end

  -- Insere a credencial no contexto do serviço
  local encoder = orb:newencoder()
  local credential = self.credentialManager:getValue()
  encoder:put(credential, self.credentialType)
  encoder:put(credential, self.credentialTypePrev)
  request.service_context =  {
    { context_id = self.contextID, context_data = encoder:getdata() }
  }

  Log:debug(format("A credencial {%s, %s, %s} foi enviada à operação %s",
      credential.identifier, credential.owner, credential.delegate,
      request.operation_name))
end
