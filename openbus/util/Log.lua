-- $Id$

local Verbose = require "loop.debug.Verbose"
local Viewer = require "loop.debug.Viewer"

---
--Mecanismo para debug do OpenBus baseado no módulo Verbose provido pelo LOOP
---
module ("openbus.util.Log", Verbose)

timed = "%d/%m/%Y %H:%M:%S"

viewer = Viewer {
  maxdepth = 2,
  indentation = "|  ",
}

_M:newlevel{"error"}
_M:newlevel{"warn"}
_M:newlevel{"info"}
_M:newlevel{"config"}
_M:newlevel{"debug"}

