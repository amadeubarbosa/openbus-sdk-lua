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
--Interceptador de requisi��es de servi�o, respons�vel por indentificar se a 
-- requisi��o � local -- mesmo processo -- e, caso afirmativo, n�o processa a
-- intercepta��o para determinadas interfaces
---
module("openbus.interceptors.SameProcessServerInterceptor", ServerInterceptor)


function __init(self, config, accessControlService, policy, localInterceptableConfig, credentialManager)
   log:interceptor("Intercepta��o Servidor -- Mesmo Processo")
   -- Obt�m as opera��es das interfaces que devem ser verificadas
   if localInterceptableConfig.interfaces then
    for _, iconfig in ipairs(localInterceptableConfig.interfaces) do
      log:interceptor(true, format("Checar interface: %s", iconfig.interface))
      for _, op in ipairs(iconfig.excluded_ops or {}) do
        Openbus:setInterceptableByLocalProcess(iconfig.interface, op, false)
        log:interceptor(format("N�o checar opera��o: %s", op))
      end
      log:interceptor(false)
    end
  else
  -- Se nenhuma interface especificada, checa todas as opera��es
     log:interceptor("checar todas as opera��es de qualquer interface")
  end
  self.credentialManager = credentialManager
  return ServerInterceptor.__init(self, config, accessControlService, policy)
end


---
--Intercepta o request para envio da informa��o de contexto (credencial)
--
--@param request Informa��es sobre a requisi��o.
---
--function receiverequest(self, request)
--  log:interceptor("INTERCEPTA��O SERVIDOR MESMO PROCESSO OP: "..request.operation_name)
--  return ServerInterceptor.receiverequest(self, request)  
--end

function checkSameProcess(self, request, clientCredential)
  local repID = request.interface.repID
  local serverCredential = self.credentialManager:getValue()
  if self:areCredentialsEqual(serverCredential,clientCredential) and
    (not Openbus:isInterceptableByLocalProcess(repID, request.operation_name)) then
    log:interceptor(">>>>>>>>>>>>>>>>>>> Chamada local n�o intercept�vel")
    return true
  end
  return false
end

--function sendreply(self, request)
--  return ServerInterceptor.sendreply(self, request)
--end
