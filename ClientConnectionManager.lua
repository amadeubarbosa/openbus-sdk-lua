-- $Id$

local log = require "openbus.common.Log"
local oop = require "loop.simple"

local ConnectionManager = require "openbus.common.ConnectionManager"

---
--Gerenciador de conexões e desconexões de clientes ao barramento
--(autenticados por user/passwordd).
---
module "openbus.common.ClientConnectionManager"

oop.class(_M, ConnectionManager)

function __init(self, accessControlServerHost, credentialHolder,
                user, password)
  local obj = 
    ConnectionManager.__init(self, accessControlServerHost, credentialHolder)
  obj.user = user
  obj.password = password
  return obj
end

---
--Conecta o cliente ao barramento com autenticação via user/password.
--@param leaseExpiredCallback Função que será executada quando o lease
--expirar.
---
function connect(self, leaseExpiredCallback)
  self.leaseExpiredCallback = leaseExpiredCallback
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
  self:completeConnection(credential, lease, 
    function() self.reconnect(self) end)
  return true
end

---
--Reconecta o cliente após uma expiração de lease.
---
function reconnect(self)
  log:conn("ClientConnectionManager: reconectando "..self.user)
  if self:connect(self.leaseExpiredCallback) then
    log:conn("ClientConnectionManager: "..self.user.." reconectado")
    if self.leaseExpiredCallback then
      self.leaseExpiredCallback()
    end
  else
    log:error("ClientConnectionManager: insucesso na reconexão de "..self.user)
  end
end
