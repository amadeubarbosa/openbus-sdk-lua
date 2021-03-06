local _G = require "_G"
local assert = _G.assert
local pcall = _G.pcall
local giop = require "oil.corba.giop"
local openbus = require "openbus"
local libidl = require "openbus.idl"
local idl = require "openbus.core.idl"
local log = require "openbus.util.logger"
local util = require "openbus.util.server"

local sysex = giop.SystemExceptionIDs

require "openbus.test.util"

setorbcfg(...)

busref = assert(util.readfrom(busref, "r"))
syskey = assert(openbus.readKeyFile(syskey))

local connprops = { accesskey = openbus.newKey() }

local orb = openbus.initORB(orbcfg)
local OpenBusContext = orb.OpenBusContext
assert(OpenBusContext.orb == orb)
busref = orb:newproxy(busref, nil, "::scs::core::IComponent")

do log:TEST("Encode illegal argument")
  local illegalchains = {
    false,
    true,
    0,
    "",
    function () end,
    coroutine.running(),
    io.stdout,
  }
  for index = 1, 1+#illegalchains do
    local illegal = illegalchains[index]
    local ok, ex = pcall(OpenBusContext.encodeChain, OpenBusContext, illegal)
    assert(not ok)
    assert(type(ex) == "string")
    assert(ex:find("bad argument", 1, "no regex"))
  end
end

do log:TEST("Encode malformed chain")
  local malformedchains = {
    { --[[empty]] },
    {
      busid = "some fake busid",
      target = "FakeEntity",
      caller = { id = "fake login id", entity = "FakeEntity" },
      originators = {},
    },
    {
      busid = "some fake busid",
      target = "FakeEntity",
      caller = { id = "fake login id", entity = "FakeEntity" },
      originators = {},
      encoded = "some fake encoded chain",
      signature = "some fake encoded chain signature",
    },
  }
  for expected, malformed in pairs(malformedchains) do
    local ok, ex = pcall(OpenBusContext.encodeChain, OpenBusContext, malformed)
    assert(not ok)
    assert(type(ex) == "table")
    assert(ex._repid == sysex.MARSHAL)
  end
end

do log:TEST("Decode illegal argument")
  local illegalstreams = {
    false,
    true,
    0,
    { --[[empty]] },
    function () --[[empty]] end,
    coroutine.running(),
    io.stdout,
  }
  for index = 1, 1+#illegalstreams do
    local illegal = illegalstreams[index]
    local ok, ex = pcall(OpenBusContext.decodeChain, OpenBusContext, illegal)
    assert(not ok)
    assert(type(ex) == "string")
    assert(ex:find("bad argument", 1, "no regex"))
  end
end

do log:TEST("Decode malformed chain")
  local malformedstreams = {
    "",
    "some ramdom rubbish",
    "BUS\0 some ramdom short rubbish",
    "BUS\1 some ramdom short rubbish",
    "BUS\2 some ramdom short rubbish",
  }
  for _, malformed in ipairs(malformedstreams) do
    local ok, ex = pcall(OpenBusContext.decodeChain, OpenBusContext, malformed)
    assert(not ok)
    assert(ex._repid == libidl.types.InvalidEncodedStream)
    assert(ex.message ~= nil)
  end
end

do log:TEST("Encode and decode chains")
  local conn1 = OpenBusContext:connectByReference(busref, connprops)
  conn1:loginByPassword(user, password, domain)
  local conn2 = OpenBusContext:connectByReference(busref, connprops)
  conn2:loginByCertificate(system, syskey)
  assert(conn1.busid == conn2.busid)
  local busid = conn1.busid
  local login1 = conn1.login.id
  local entity1 = conn1.login.entity
  local login2 = conn2.login.id
  local entity2 = conn2.login.entity

  OpenBusContext:setDefaultConnection(conn1)
  local chain1to2 = OpenBusContext:makeChainFor(entity2)
  local stream = assert(OpenBusContext:encodeChain(chain1to2))
  assert(type(stream) == "string")
  chain1to2 = assert(OpenBusContext:decodeChain(stream))
  assert(chain1to2.busid == busid)
  assert(chain1to2.target == entity2)
  assert(chain1to2.caller.id == login1)
  assert(chain1to2.caller.entity == entity1)
  assert(#chain1to2.originators == 0)

  OpenBusContext:setDefaultConnection(conn2)
  OpenBusContext:joinChain(chain1to2)
  local chain1to2to1 = OpenBusContext:makeChainFor(entity1)

  OpenBusContext:exitChain()
  OpenBusContext:setDefaultConnection(nil)
  conn1:logout()
  conn2:logout()

  local stream = assert(OpenBusContext:encodeChain(chain1to2to1))
  assert(type(stream) == "string")
  chain1to2to1 = assert(OpenBusContext:decodeChain(stream))
  assert(chain1to2to1.busid == busid)
  assert(chain1to2to1.target == entity1)
  assert(chain1to2to1.caller.id == login2)
  assert(chain1to2to1.caller.entity == entity2)
  assert(chain1to2to1.originators[1].id == login1)
  assert(chain1to2to1.originators[1].entity == entity1)
end

orb:shutdown()
