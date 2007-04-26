-----------------------------------------------------------------------------
-- Objeto que é responsável por renovar o lease junto a um Provider
--
-- Última alteração:
--   $Id:$
-----------------------------------------------------------------------------

local oil = require"oil"
local oop = require "loop.base"
local Timer = require "loop.thread.Timer"
local log = require "openbus.common.Log"

module ("openbus.common.LeaseHolder", oop.class)

-- Constrói o holder
function __init(self, lease, credential, leaseProvider)
  log:lease("Lease set to "..lease)
  return oop.rawnew(self,
    { lease = lease,
      credential = credential,
      provider = leaseProvider,
    })
end

function setLease(self, lease)
  self.lease = lease
  log:lease("Lease set to "..lease)
end

function getLease(self)
  return self.lease
end

function setProvider(self, provider)
  self.provider = provider
end

function getProvider(self)
  return self.provider
end

function startRenew(self)
  if not self.timer then
    -- Aloca uma "thread" para a renovação do lease
    local timer = Timer{
      scheduler = oil.scheduler,
      rate = self.lease,
    }
    function timer.action(timer)
      -- self é o leaseHolder
      local granted, newlease =
        self:getProvider():renewLease(self.credential)
      if not granted then
        timer:disable()
        return
      end
      if timer.rate ~= newlease then
        timer.rate = newlease
        self:setLease(newlease)
      end
    end
    self.timer = timer
  end
  self.timer.rate = self.lease
  self.timer:enable()
end

function stopRenew(self)
  self.timer:disable()
end
