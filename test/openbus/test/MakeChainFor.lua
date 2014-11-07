local _G = require "_G"
local assert = _G.assert
local pcall = _G.pcall
local giop = require "oil.corba.giop"
local openbus = require "openbus"
local idl = require "openbus.core.idl"
local log = require "openbus.util.logger"

local sysex = giop.SystemExceptionIDs

bushost, busport, verbose = ...
require "openbus.test.configs"

syskey = assert(openbus.readKeyFile(syskey))

local connprops = { accesskey = openbus.newKey() }

local orb = openbus.initORB()
local OpenBusContext = orb.OpenBusContext
assert(OpenBusContext.orb == orb)



do log:TEST("Make chains for active logins")
  local conn1 = OpenBusContext:createConnection(bushost, busport, connprops)
  conn1:loginByPassword(user, password)
  local conn2 = OpenBusContext:createConnection(bushost, busport, connprops)
  conn2:loginByCertificate(system, syskey)
  assert(conn1.busid == conn2.busid)
  local busid = conn1.busid
  local login1 = conn1.login.id
  local entity1 = conn1.login.entity
  local login2 = conn2.login.id
  local entity2 = conn2.login.entity

  OpenBusContext:setDefaultConnection(conn1)
  local chain1to2 = OpenBusContext:makeChainFor(entity2)
  assert(chain1to2.busid == busid)
  assert(chain1to2.target == entity2)
  assert(chain1to2.caller.id == login1)
  assert(chain1to2.caller.entity == entity1)
  assert(#chain1to2.originators == 0)

  OpenBusContext:joinChain(chain1to2)
  local ok, ex = pcall(OpenBusContext.makeChainFor, OpenBusContext, entity1)
  assert(not ok)
  assert(ex._repid == sysex.NO_PERMISSION)
  assert(ex.completed == "COMPLETED_NO")
  assert(ex.minor == idl.const.services.access_control.InvalidChainCode)

  OpenBusContext:setDefaultConnection(conn2)
  local chain1to2to1 = OpenBusContext:makeChainFor(entity1)
  assert(chain1to2to1.busid == busid)
  assert(chain1to2to1.target == entity1)
  assert(chain1to2to1.caller.id == login2)
  assert(chain1to2to1.caller.entity == entity2)
  assert(chain1to2to1.originators[1].id == login1)
  assert(chain1to2to1.originators[1].entity == entity1)
  OpenBusContext:exitChain()

  OpenBusContext:setDefaultConnection(nil)
  conn1:logout()
  conn2:logout()
end

do log:TEST("Fail to make chain for invalid logins")
  local conn = OpenBusContext:createConnection(bushost, busport, connprops)
  conn:loginByPassword(user, password)
  OpenBusContext:setDefaultConnection(conn)
  
  local FakeEntity = "Fake Entity"
  local chain = OpenBusContext:makeChainFor(FakeEntity)
  assert(chain.busid == conn.busid)
  assert(chain.target == FakeEntity)
  assert(chain.caller.id == conn.login.id)
  assert(chain.caller.entity == user)
  assert(#chain.originators == 0)
  
  OpenBusContext:setDefaultConnection(nil)
  conn:logout()
end

do log:TEST("Fail to make chain without login")
  local ok, ex = pcall(OpenBusContext.makeChainFor, OpenBusContext, user)
  assert(not ok)
  assert(ex._repid == sysex.NO_PERMISSION)
  assert(ex.completed == "COMPLETED_NO")
  assert(ex.minor == idl.const.services.access_control.NoLoginCode)
  
  local conn = OpenBusContext:createConnection(bushost, busport, connprops)
  OpenBusContext:setDefaultConnection(conn)

  local ok, ex = pcall(OpenBusContext.makeChainFor, OpenBusContext, user)
  assert(not ok)
  assert(ex._repid == sysex.NO_PERMISSION)
  assert(ex.completed == "COMPLETED_NO")
  assert(ex.minor == idl.const.services.access_control.NoLoginCode)
  
  conn:loginByPassword(user, password)
  conn:logout()
  
  local ok, ex = pcall(OpenBusContext.makeChainFor, OpenBusContext, user)
  assert(not ok)
  assert(ex._repid == sysex.NO_PERMISSION)
  assert(ex.completed == "COMPLETED_NO")
  assert(ex.minor == idl.const.services.access_control.NoLoginCode)
  
  OpenBusContext:setDefaultConnection(nil)
end

orb:shutdown()
