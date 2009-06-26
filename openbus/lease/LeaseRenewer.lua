-- $Id$

local oil = require"oil"
local oop = require "loop.base"
local Timer = require "loop.thread.Timer"
local log = require "openbus.util.Log"

local tostring = tostring

---
--Objeto que é responsável por renovar o lease junto a um Provider.
---
module ("openbus.lease.LeaseRenewer", oop.class)

---
--Constrói o renovador de lease.
--
--@param lease O período de tempo entre as renovações do lease.
--@param credential A credencial do membro.
--@param leaseProvider A entidade onde se deve renovar o lease.
--@param leaseExpiredCallback Instância de LeaseExpiredCallback que será
--       executada quando o lease expirar.
--
--@return O renovador de lease.
---
function __init(self, lease, credential, leaseProvider, leaseExpiredCallback)
  log:lease("Lease set to "..lease)
  return oop.rawnew(self,
    { lease = lease,
      credential = credential,
      provider = leaseProvider,
      leaseExpiredCallback = leaseExpiredCallback, -- opcional
    })
end

---
--Define por quanto tempo o lease será válido.
--
--@param lease O tempo de validade do lease.
---
function setLease(self, lease)
  self.lease = lease
  log:lease("Lease set to "..lease)
end

---
--Obtém o tempo de validade do lease.
--
--@return O tempo de validade do lease.
---
function getLease(self)
  return self.lease
end

---
--Define o provedor responsável pelo lease, ou seja, onde o lease deve ser
--renovado.
--
--@provider O provedor.
---
function setProvider(self, provider)
  self.provider = provider
end

---
--Obtém o provedor do lease.
--
--@return O provedor do lease.
---
function getProvider(self)
  return self.provider
end

---
--Inicia a execução do renovador de lease.
---
function startRenew(self)
  if not self.timer then
    -- Aloca uma "thread" para a renovação do lease
    local timer = Timer{
      scheduler = oil.tasks,
      rate = self.lease,
    }
    function timer.action(timer)
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
          self.leaseExpiredCallback:expired()
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

---
--Termina a execução do renovador.
---
function stopRenew(self)
  self.timer:disable()
end
