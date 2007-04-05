--
-- Interceptador de requisições de serviço, responsável por inserir no
--   contexto da requisição a credencial do cliente
--
local oil = require "oil"
local oop = require "loop.base"

local verbose = require "openbus.common.Log"

module("openbus.common.ClientInterceptor", oop.class)

-- Constrói o interceptador
function __init(self, config, credentialHolder)

  verbose:interceptor("Construindo interceptador para cliente")
  local lir = oil.getLIR()
  return oop.rawnew(self, 
                    {credentialHolder = credentialHolder,
                     credentialType = lir:lookup_id(config.credential_type).type,
                     contextID = config.contextID})
end

-- Intercepta o request para envio da informação de contexto (credencial)
function sendrequest(self, request)
  verbose:interceptor("INTERCEPTAÇÂO CLIENTE OP: "..request.operation)

  -- Verifica de existe credencial para envio
  if not self.credentialHolder:hasValue() then
    verbose:interceptor "SEM CREDENCIAL !"
    return
  end
  verbose:interceptor("TEM CREDENCIAL!")

  -- Insere a credencial no contexto do serviço
  local encoder = oil.newencoder()
  encoder:put(self.credentialHolder:getValue(), 
              self.credentialType)
  request.service_context =  {
    { context_id = self.contextID, context_data = encoder:getdata() }
  }
  verbose:interceptor("INSERI CREDENCIAL")
end

function receivereply(reply)
end
