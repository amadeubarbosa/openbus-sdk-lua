-----------------------------------------------------------------------------
-- Gerenciador de conex�es e desconex�es de clientes ao barramento
-- (autenticados por user/passwordd)
-- 
-- �ltima altera��o:
--   $Id$
-----------------------------------------------------------------------------
local log = require "openbus.common.Log"
local oop = require "loop.simple"

local ConnectionManager = require "openbus.common.ConnectionManager"

module("openbus.common.ClientConnectionManager", oop.class, ConnectionManager)

function __init(self, accessControlServerHost, credentialHolder, 
                user, password)
  local obj = { accessControlServerHost = accessControlServerHost, 
                credentialHolder = credentialHolder,
                user = user, password = password }
  ConnectionManager:__init(obj)
  return oop.rawnew(self, obj)
end

--
-- Conecta o servi�o ao barramento com autentica��o via user/password
--
function connect(self)
  local accessControlService = self:getAccessControlService()
  if accessControlService == nil then
    return false
  end
  local success, credential, lease =
    accessControlService:loginByPassword(self.user, self.password)
  if not success then
    log:error("ClientConnectionManager: insucesso no login de "..self.user)
    return false
  end
  self:completeConnection(credential, lease)
  return true
end
