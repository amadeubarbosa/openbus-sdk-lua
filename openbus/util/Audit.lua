-- $Id$

local oop = require "loop.base"

local Verbose = require "loop.debug.Verbose"
local Viewer = require "loop.debug.Viewer"

module ("openbus.util.Audit", Verbose)

timed = "%d/%m/%Y %H:%M:%S"

viewer = Viewer {
  maxdepth = 2,
  indentation = "|  ",
}

groups.audit = {
  "login_password", "login_certificate", "logout",
  "register", "unregister",
  "uptime",
}

groups.all = {"audit",}

_M:newlevel{"audit"}

