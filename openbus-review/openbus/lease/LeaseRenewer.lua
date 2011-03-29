-- $Id$

local oil = require"oil"
local oop = require "loop.base"
local Timer = require "loop.thread.Timer"
local Log = require "openbus.util.Log"

local tostring = tostring
local format = string.format

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
  Log:debug(format("O tempo de dura��o de lease foi definido para %d segundos",
      lease))
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
  Log:debug(format("O tempo de dura��o de lease foi definido para %d segundos",
      lease))
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
--Define o observador do lease.
--
--@lec o Observador.
---
function setLeaseExpiredCallback(self, lec)
  self.leaseExpiredCallback = lec
end

---
--Inicia a execu��o do renovador de lease.
---
function startRenew(self)
  if not self.timer then
    self.timer = self:_createTimer()
  end
  self.timer.rate = self.lease
  self.timer:enable()
end

function _createTimer(self)
  -- Aloca uma "thread" para a renova��o do lease
  return Timer{
    scheduler = oil.tasks,
    rate = self.lease,
    action = _renewLeaseAction,
    leaseRenewer = self,
  }
end

function _renewLeaseAction(timer)
  local provider = timer.leaseRenewer:getProvider()
  local success, granted, newlease  =
      oil.pcall(provider.renewLease, provider, timer.leaseRenewer.credential)
  if success and granted then
    if timer.rate ~= newlease then
      timer.rate = newlease
      timer.leaseRenewer:setLease(newlease)
    end
  else
    if not success and granted[1] ~= "IDL:omg.org/CORBA/NO_PERMISSION:1.0" then
      Log:warn("Ocorreu um erro na comunica��o com o provedor do lease: ",
          granted)
    else -- not granted or granted[1] == "IDL:omg.org/CORBA/NO_PERMISSION:1.0"
      Log:debug("O lease n�o foi renovado porque a credencial expirou")
      if timer.leaseRenewer.leaseExpiredCallback then
        timer.leaseRenewer.leaseExpiredCallback:expired()
      end
      timer:disable()
    end
  end
end

---
--Termina a execu��o do renovador.
---
function stopRenew(self)
  self.timer:disable()
  self.timer.scheduler:remove(self.timer.thread)
end
