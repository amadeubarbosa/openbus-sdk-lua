-----------------------------------------------------------------------------
-- Interceptador de requisi��es de servi�o, respons�vel por inserir no
--   contexto da requisi��o a credencial do cliente
--
-- �ltima altera��o:
--   $Id$
-----------------------------------------------------------------------------
local oil = require "oil"
local oop = require "loop.base"

local log = require "openbus.common.Log"

module("openbus.common.ClientInterceptor", oop.class)

-- Constr�i o interceptador
function __init(self, config, credentialHolder)

  log:interceptor("Construindo interceptador para cliente")
  local lir = oil.getLIR()
  return oop.rawnew(self, 
                    {credentialHolder = credentialHolder,
                     credentialType = lir:lookup_id(config.credential_type).type,
                     contextID = config.contextID})
end

-- Intercepta o request para envio da informa��o de contexto (credencial)
function sendrequest(self, request)
  log:interceptor("INTERCEPTA��O CLIENTE OP: "..request.operation)

  -- Verifica de existe credencial para envio
  if not self.credentialHolder:hasValue() then
    log:interceptor "SEM CREDENCIAL !"
    return
  end
  log:interceptor("TEM CREDENCIAL!")

  -- Insere a credencial no contexto do servi�o
  local encoder = oil.newencoder()
  encoder:put(self.credentialHolder:getValue(), 
              self.credentialType)
  request.service_context =  {
    { context_id = self.contextID, context_data = encoder:getdata() }
  }
  log:interceptor("INSERI CREDENCIAL")
end

function receivereply(reply)
end
