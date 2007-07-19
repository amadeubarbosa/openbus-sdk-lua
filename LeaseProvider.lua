-----------------------------------------------------------------------------
-- Objeto que é responsável por verificar os leases oferecidos
--
-- Última alteração:
--   $Id$
-----------------------------------------------------------------------------

local oil = require"oil"
local oop = require "loop.base"
local Timer = require "loop.thread.Timer"
local log = require "openbus.common.Log"

module ("openbus.common.LeaseProvider", oop.class)

-- Constrói o provider
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

function setCheckLeasesFunction(self, checkLeases)
  self.timer.action = checkLeases
end

function setRate(self, rate)
  self.timer.rate = rate
end

function startCheck(self)
  self.timer:enable()
end

function stopCheck(self)
  self.timer:disable()
end
