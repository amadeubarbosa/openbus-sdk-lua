
local oil = require "oil"
local orb = oil.orb

local log = require "openbus.common.Log"

local ClientInterceptor = require "openbus.common.ClientInterceptor"

--local FTManager = require "openbus.common.FTManager"

local faultTolerantManager = {}
---
--Interceptador de requisições de serviço tolerantes a falhas,
---

module("openbus.common.FTClientInterceptor", ClientInterceptor)

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
  log:faulttolerance("[FTClientInterceptor] Instanciando o FTManager")
--  faultTolerantManager = FTManager()
  return ClientInterceptor:__init(config, credentialManager)
end

---
--Intercepta o request para envio da informação de contexto (credencial)
--
--@param request Informações sobre a requisição.
---
function sendrequest(self, request)
   log:faulttolerance("[FTClientInterceptor] Interceptando request")
--faultTolerantManager
    return ClientInterceptor:sendrequest(request)
end
