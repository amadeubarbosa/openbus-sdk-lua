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

local tostring = tostring

module ("openbus.common.LeaseHolder", oop.class)

-- Constrói o holder
function __init(self, lease, credential, leaseProvider, leaseExpiredCallback)
  log:lease("Lease set to "..lease)
  return oop.rawnew(self,
    { lease = lease,
      credential = credential,
      provider = leaseProvider,
      leaseExpiredCallback = leaseExpiredCallback, -- opcional
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
      local provider = self:getProvider()
      local success, granted, newlease  =
        oil.pcall(provider.renewLease, provider, self.credential)
      if not success then
        -- Quando ocorre falha no acesso ao provedor, tenta renovar com
        -- uma freqüência maior.
        log:warn("Falha na acessibilidade ao provedor do lease.")
--      log:warn("Falha na acessibilidade ao provedor do lease:"..
--        tostring(granted).."\n")
        timer.rate = (self.retrying and timer.rate) or (timer.rate /2)
        self.retrying = true
        return
      end
      self.retrying = false
      if not granted then
        log:lease("Lease não renovado.")
        timer:disable()
        if self.leaseExpiredCallback then
          self:leaseExpiredCallback()
        end
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
