local _G = require "_G"
local assert = _G.assert
local error = _G.error
local ipairs = _G.ipairs
local pairs = _G.pairs
local pcall = _G.pcall
local type = _G.type
local coroutine = require "coroutine"
local string = require "string"
local io = require "io"
local uuid = require "uuid"
local giop = require "oil.corba.giop"
local cothread = require "cothread"
local openbus = require "openbus"
local libidl = require "openbus.idl"
local idl = require "openbus.core.idl"
local msg = require "openbus.util.messages"
local log = require "openbus.util.logger"

local sysex = giop.SystemExceptionIDs

bushost, busport, verbose = ...
require "openbus.test.configs"

syskey = assert(openbus.readKeyFile(syskey))

local smalltime = .1
local connprops = { accesskey = openbus.newKey() }

local orb = openbus.initORB()
local OpenBusContext = orb.OpenBusContext
assert(OpenBusContext.orb == orb)



do log:TEST("Make chains for active logins")
  local conn1 = OpenBusContext:createConnection(bushost, busport, connprops)
  conn1:loginByPassword(user, password)
  local conn2 = OpenBusContext:createConnection(bushost, busport, connprops)
  conn2:loginByCertificate(system, syskey)

  OpenBusContext:setDefaultConnection(conn1)
  local chain1to2 = OpenBusContext:makeChainFor(conn2.login.id)
  assert(chain1to2.target == conn2.login.entity)
  assert(chain1to2.caller.id == conn1.login.id)
  assert(chain1to2.caller.entity == conn1.login.entity)
  assert(#chain1to2.originators == 0)

  OpenBusContext:joinChain(chain1to2)
  local ok, ex = pcall(OpenBusContext.makeChainFor, OpenBusContext, conn1.login.id)
  assert(not ok)
  assert(ex._repid == sysex.NO_PERMISSION)
  assert(ex.completed == "COMPLETED_NO")
  assert(ex.minor == idl.const.services.access_control.InvalidChainCode)

  OpenBusContext:setDefaultConnection(conn2)
  local chain1to2to1 = OpenBusContext:makeChainFor(conn1.login.id)
  assert(chain1to2to1.target == conn1.login.entity)
  assert(chain1to2to1.caller.id == conn2.login.id)
  assert(chain1to2to1.caller.entity == conn2.login.entity)
  assert(chain1to2to1.originators[1].id == conn1.login.id)
  assert(chain1to2to1.originators[1].entity == conn1.login.entity)
  OpenBusContext:exitChain()

  OpenBusContext:setDefaultConnection(nil)
  conn1:logout()
  conn2:logout()
end

do log:TEST("Fail to make chain for invalid logins")
  local conn = OpenBusContext:createConnection(bushost, busport, connprops)
  conn:loginByPassword(user, password)
  OpenBusContext:setDefaultConnection(conn)
  
  local ok, ex = pcall(OpenBusContext.makeChainFor, OpenBusContext, "invalid login")
  assert(not ok)
  assert(ex._repid == idl.types.services.access_control.InvalidLogins)
  assert(ex.loginIds[1] == "invalid login")
  
  OpenBusContext:setDefaultConnection(nil)
  conn:logout()
end

do log:TEST("Fail to make chain without login")
  local ok, ex = pcall(OpenBusContext.makeChainFor, OpenBusContext, "invalid login")
  assert(not ok)
  assert(ex._repid == sysex.NO_PERMISSION)
  assert(ex.completed == "COMPLETED_NO")
  assert(ex.minor == idl.const.services.access_control.NoLoginCode)
  
  local conn = OpenBusContext:createConnection(bushost, busport, connprops)
  OpenBusContext:setDefaultConnection(conn)

  local ok, ex = pcall(OpenBusContext.makeChainFor, OpenBusContext, "invalid login")
  assert(not ok)
  assert(ex._repid == sysex.NO_PERMISSION)
  assert(ex.completed == "COMPLETED_NO")
  assert(ex.minor == idl.const.services.access_control.NoLoginCode)
  
  conn:loginByPassword(user, password)
  conn:logout()
  
  local ok, ex = pcall(OpenBusContext.makeChainFor, OpenBusContext, "invalid login")
  assert(not ok)
  assert(ex._repid == sysex.NO_PERMISSION)
  assert(ex.completed == "COMPLETED_NO")
  assert(ex.minor == idl.const.services.access_control.NoLoginCode)
  
  OpenBusContext:setDefaultConnection(nil)
end

orb:shutdown()
