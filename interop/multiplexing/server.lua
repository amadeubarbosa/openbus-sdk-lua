local log = require "openbus.util.logger"
local openbus = require "openbus"
local ComponentContext = require "scs.core.ComponentContext"

bushost, busport, verbose = ...
require "openbus.util.testcfg"

-- setup and start the ORB
local orb1 = openbus.initORB()
orb1:loadidlfile("hello.idl")
openbus.newthread(orb1.run, orb1)
local conns1 = orb1.OpenBusConnectionManager
local orb2 = openbus.initORB()
orb2:loadidlfile("hello.idl")
openbus.newthread(orb2.run, orb2)
local conns2 = orb2.OpenBusConnectionManager

-- connect to the bus
local conn1AtBus1WithOrb1 = conns1:createConnection(bushost, busport)
local conn2AtBus1WithOrb1 = conns1:createConnection(bushost, busport)
local connAtBus2WithOrb1 = conns1:createConnection(bus2host, bus2port)
local connAtBus1WithOrb2 = conns2:createConnection(bushost, busport)

-- create service implementation
local hello = {}
function hello:sayHello()
  local chain = conn1AtBus1WithOrb1:getCallerChain()
             or connAtBus2WithOrb1:getCallerChain()
             or connAtBus1WithOrb2:getCallerChain()
  return "Hello from "..chain.caller.entity.."@"..chain.busid.."!"
end

-- create service SCS component
local iface = "tecgraf::openbus::interop::simple::Hello"
local component1 = ComponentContext(orb1, {
  name = "Hello",
  major_version = 1,
  minor_version = 0,
  patch_version = 0,
  platform_spec = "",
})
component1:addFacet("Hello", orb1.types:lookup(iface).repID, hello)
local component2 = ComponentContext(orb2, {
  name = "Hello",
  major_version = 1,
  minor_version = 0,
  patch_version = 0,
  platform_spec = "",
})
component2:addFacet("Hello", orb2.types:lookup(iface).repID, hello)

-- set incoming connections
conns1:setDispatcher(conn1AtBus1WithOrb1)
conns1:setDispatcher(connAtBus2WithOrb1)

-- set outgoing connections
conns1:setRequester(connAtBus2WithOrb1)
conns2:setDefaultConnection(connAtBus1WithOrb2)

-- login to the bus
conn1AtBus1WithOrb1:loginByCertificate(system, syskey)
conn2AtBus1WithOrb1:loginByCertificate(system, syskey)
connAtBus2WithOrb1:loginByCertificate(system, syskey)
connAtBus1WithOrb2:loginByCertificate(system, syskey)

-- offer the service
openbus.newthread(function()
  conns1:setRequester(conn1AtBus1WithOrb1)
  conn1AtBus1WithOrb1.offers:registerService(component1.IComponent, {
    {name="offer.domain",value="Interoperability Tests"}, -- provided property
  })
end)
openbus.newthread(function()
  conns1:setRequester(conn2AtBus1WithOrb1)
  conn2AtBus1WithOrb1.offers:registerService(component1.IComponent, {
    {name="offer.domain",value="Interoperability Tests"}, -- provided property
  })
end)
connAtBus2WithOrb1.offers:registerService(component1.IComponent, {
  {name="offer.domain",value="Interoperability Tests"}, -- provided property
})
connAtBus1WithOrb2.offers:registerService(component2.IComponent, {
  {name="offer.domain",value="Interoperability Tests"}, -- provided property
})
