local ipairs = ipairs
local format = string.format
local oil = require "oil"
local orb = oil.orb

local oop = require "loop.base"
local log = require "openbus.util.Log"
local Openbus = require "openbus.Openbus"
local Utils = require "openbus.util.Utils"
local ServerInterceptor = require "openbus.interceptors.ServerInterceptor"
---
--Interceptador de requisições de serviço, responsável por indentificar se a 
-- requisição é local -- mesmo processo -- e, caso afirmativo, não processa a
-- interceptação para determinadas interfaces
---
module("openbus.interceptors.SameProcessServerInterceptor", ServerInterceptor)


function __init(self, config, accessControlService, policy, localInterceptableConfig, credentialManager)
   log:interceptor("Interceptação Servidor -- Mesmo Processo")
   -- Obtém as operações das interfaces que devem ser verificadas
   if localInterceptableConfig.interfaces then
    for _, iconfig in ipairs(localInterceptableConfig.interfaces) do
      log:interceptor(true, format("Checar interface: %s", iconfig.interface))
      for _, op in ipairs(iconfig.excluded_ops or {}) do
        Openbus:setInterceptableByLocalProcess(iconfig.interface, op, false)
        log:interceptor(format("Não checar operação: %s", op))
      end
      log:interceptor(false)
    end
  else
  -- Se nenhuma interface especificada, checa todas as operações
     log:interceptor("checar todas as operações de qualquer interface")
  end
  self.credentialManager = credentialManager
  return ServerInterceptor.__init(self, config, accessControlService, policy)
end


---
--Intercepta o request para envio da informação de contexto (credencial)
--
--@param request Informações sobre a requisição.
---
--function receiverequest(self, request)
--  log:interceptor("INTERCEPTAÇÂO SERVIDOR MESMO PROCESSO OP: "..request.operation_name)
--  return ServerInterceptor.receiverequest(self, request)  
--end

function checkSameProcess(self, request, clientCredential)
  local repID = request.interface.repID
  local serverCredential = self.credentialManager:getValue()
  if self:areCredentialsEqual(serverCredential,clientCredential) and
    (not Openbus:isInterceptableByLocalProcess(repID, request.operation_name)) then
    log:interceptor(">>>>>>>>>>>>>>>>>>> Chamada local não interceptável")
    return true
  end
  return false
end

--function sendreply(self, request)
--  return ServerInterceptor.sendreply(self, request)
--end
