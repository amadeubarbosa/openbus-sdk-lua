local log = require "openbus.util.logger"
local server = require "openbus.util.server"
local openbus = require "openbus"
local ComponentContext = require "scs.core.ComponentContext"

require "openbus.test.util"

-- setup and start the ORB
local orb1 = openbus.initORB()
orb1:loadidlfile("hello.idl")
openbus.newthread(orb1.run, orb1)
local orb2 = openbus.initORB()
orb2:loadidlfile("hello.idl")
openbus.newthread(orb2.run, orb2)
local iface = orb1.types:lookup("tecgraf::openbus::interop::simple::Hello")

-- customize test configuration for this case
settestcfg(iface, ...)

-- connect to the buses
local conns1 = orb1.OpenBusConnectionManager
local conns2 = orb2.OpenBusConnectionManager
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

-- create service SCS components
local compId = {
  name = "Hello",
  major_version = 1,
  minor_version = 0,
  patch_version = 0,
  platform_spec = "",
}
local component1 = ComponentContext(orb1, compId)
local component2 = ComponentContext(orb2, compId)
component1:addFacet(iface.name, iface.repID, hello)
component2:addFacet(iface.name, iface.repID, hello)

-- set incoming connections
conns1:setDispatcher(conn1AtBus1WithOrb1)
conns1:setDispatcher(connAtBus2WithOrb1)

-- set outgoing connections
conns1:setRequester(connAtBus2WithOrb1)
conns2:setDefaultConnection(connAtBus1WithOrb2)

-- login to the bus
local prvkey = assert(server.readfrom(syskey))
conn1AtBus1WithOrb1:loginByCertificate(system, prvkey)
conn2AtBus1WithOrb1:loginByCertificate(system, prvkey)
connAtBus2WithOrb1:loginByCertificate(system, prvkey)
connAtBus1WithOrb2:loginByCertificate(system, prvkey)

-- offer the service
openbus.newthread(function()
  conns1:setRequester(conn1AtBus1WithOrb1)
  conn1AtBus1WithOrb1.offers:registerService(component1.IComponent, properties)
end)
openbus.newthread(function()
  conns1:setRequester(conn2AtBus1WithOrb1)
  conn2AtBus1WithOrb1.offers:registerService(component1.IComponent, properties)
end)
connAtBus2WithOrb1.offers:registerService(component1.IComponent, properties)
connAtBus1WithOrb2.offers:registerService(component2.IComponent, properties)
