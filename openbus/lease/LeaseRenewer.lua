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
--Define o observador do lease.
--
--@lec o Observador.
---
function setLeaseExpiredCallback(self, lec)
  self.leaseExpiredCallback = lec
end

---
--Inicia a execução do renovador de lease.
---
function startRenew(self)
  if not self.timer then
    self.timer = self:_createTimer()
  end
  self.timer.rate = self.lease
  self.timer:enable()
end

function _createTimer(self)
  -- Aloca uma "thread" para a renovação do lease
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
      -- Quando ocorre falha no acesso ao provedor, tenta renovar com
      -- uma freqüência maior.
      -- log:warn("Falha na acessibilidade ao provedor do lease.")
      log:warn("Falha na acessibilidade ao provedor do lease:", granted)
    else -- not granted or granted[1] == "IDL:omg.org/CORBA/NO_PERMISSION:1.0"
      log:lease("Lease não renovado, credencial expirou.")
      timer:disable()
      if timer.leaseExpiredCallback then
        timer.leaseExpiredCallback:expired()
      end
    end
  end
end

---
--Termina a execução do renovador.
---
function stopRenew(self)
  self.timer:disable()
end
