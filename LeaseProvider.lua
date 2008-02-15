-- $Id$

local oil = require"oil"
local oop = require "loop.base"
local Timer = require "loop.thread.Timer"
local log = require "openbus.common.Log"

---
--Responsável por verificar os leases oferecidos.
---
module ("openbus.common.LeaseProvider", oop.class)

---
--Cria o provedor de leases.
--
--@param checkLease A função responsável por verificar os leases.
--@param rate O período de tempo entre as renovações dos leases.
--
--@return O provedor de leases.
---
function __init(self, checkLeases, rate)
  local timer = Timer{
    scheduler = oil.tasks,
    action = checkLeases,
    rate = rate,
  }
  local newObj = oop.rawnew(self,
    { timer = timer,
    })
  newObj:startCheck()
  return newObj
end

---
--Define a função responsável por verificar os leases.
--
--@param checkLeases A função responsável por verificar os leases.
---
function setCheckLeasesFunction(self, checkLeases)
  self.timer.action = checkLeases
end

---
--DEefine o intervalo de tempo em que os leases devem ser verificados.
--
--@param rate O intervalo.
---
function setRate(self, rate)
  self.timer.rate = rate
end

---
--Inicia a execução do verificador de leases.
---
function startCheck(self)
  self.timer:enable()
end

---
--Interrompe a execução do verificador de leases.
---
function stopCheck(self)
  self.timer:disable()
end
