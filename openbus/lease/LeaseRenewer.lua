-- $Id$

local oil = require"oil"
local oop = require "loop.base"
local Timer = require "loop.thread.Timer"
local log = require "openbus.util.Log"

local tostring = tostring

---
--Objeto que � respons�vel por renovar o lease junto a um Provider.
---
module ("openbus.lease.LeaseRenewer", oop.class)

---
--Constr�i o renovador de lease.
--
--@param lease O per�odo de tempo entre as renova��es do lease.
--@param credential A credencial do membro.
--@param leaseProvider A entidade onde se deve renovar o lease.
--@param leaseExpiredCallback Inst�ncia de LeaseExpiredCallback que ser�
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
--Define por quanto tempo o lease ser� v�lido.
--
--@param lease O tempo de validade do lease.
---
function setLease(self, lease)
  self.lease = lease
  log:lease("Lease set to "..lease)
end

---
--Obt�m o tempo de validade do lease.
--
--@return O tempo de validade do lease.
---
function getLease(self)
  return self.lease
end

---
--Define o provedor respons�vel pelo lease, ou seja, onde o lease deve ser
--renovado.
--
--@provider O provedor.
---
function setProvider(self, provider)
  self.provider = provider
end

---
--Obt�m o provedor do lease.
--
--@return O provedor do lease.
---
function getProvider(self)
  return self.provider
end

---
--Inicia a execu��o do renovador de lease.
---
function startRenew(self)
  if not self.timer then
    -- Aloca uma "thread" para a renova��o do lease
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
        -- uma freq��ncia maior.
        log:warn("Falha na acessibilidade ao provedor do lease.")
--      log:warn("Falha na acessibilidade ao provedor do lease:"..
--        tostring(granted).."\n")
        timer.rate = (self.retrying and timer.rate) or (timer.rate /2)
        self.retrying = true
        return
      end
      self.retrying = false
      if not granted then
        log:lease("Lease n�o renovado.")
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
--Termina a execu��o do renovador.
---
function stopRenew(self)
  self.timer:disable()
end
