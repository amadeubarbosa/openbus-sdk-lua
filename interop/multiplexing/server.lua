local openbus = require "openbus"
local log = require "openbus.util.logger"
local ComponentContext = require "scs.core.ComponentContext"

require "openbus.test.util"

-- setup and start the ORBs
settestcfg(...)
local orb1 = openbus.initORB(orbcfg)
settestcfg(...)
local orb2 = openbus.initORB(orbcfg)

-- load interface definition
orb1:loadidlfile("idl/hello.idl")
orb2:loadidlfile("idl/hello.idl")
local iface = orb1.types:lookup("tecgraf::openbus::interop::simple::Hello")

-- get bus context manager
local OpenBusContext1 = orb1.OpenBusContext
local OpenBusContext2 = orb2.OpenBusContext

-- create service implementation
local hello = {}
function hello:sayHello()
  local chain = OpenBusContext1:getCallerChain()
             or OpenBusContext2:getCallerChain()
  local entity = chain.caller.entity.."@"..chain.busid
  log:TEST("got call from ",entity)
  return "Hello "..entity.."!"
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

-- connect to the buses
local conn1AtBus1WithOrb1 = OpenBusContext1:createConnection(bushost, busport)
local conn2AtBus1WithOrb1 = OpenBusContext1:createConnection(bushost, busport)
local connAtBus2WithOrb1 = OpenBusContext1:createConnection(bus2host, bus2port)
local connAtBus1WithOrb2 = OpenBusContext2:createConnection(bushost, busport)

-- set incoming connections
function OpenBusContext1:onCallDispatch(busid, login, objkey, operation, ...)
  if busid == conn1AtBus1WithOrb1.busid then
    return conn1AtBus1WithOrb1
  elseif busid == connAtBus2WithOrb1.busid then
    return connAtBus2WithOrb1
  end
end

-- set outgoing connections
OpenBusContext1:setCurrentConnection(connAtBus2WithOrb1)
OpenBusContext2:setDefaultConnection(connAtBus1WithOrb2)

-- login to the bus
local prvkey = assert(openbus.readKeyFile(syskey))
conn1AtBus1WithOrb1:loginByCertificate(system, prvkey)
conn2AtBus1WithOrb1:loginByCertificate(system, prvkey)
connAtBus2WithOrb1:loginByCertificate(system, prvkey)
connAtBus1WithOrb2:loginByCertificate(system, prvkey)

-- offer the service
openbus.newThread(function()
  OpenBusContext1:setCurrentConnection(conn1AtBus1WithOrb1)
  local OfferRegistry = OpenBusContext1:getOfferRegistry()
  OfferRegistry:registerService(component1.IComponent, properties)
end)
openbus.newThread(function()
  OpenBusContext1:setCurrentConnection(conn2AtBus1WithOrb1)
  local OfferRegistry = OpenBusContext1:getOfferRegistry()
  OfferRegistry:registerService(component1.IComponent, properties)
end)
local OfferRegistry1 = OpenBusContext1:getOfferRegistry()
OfferRegistry1:registerService(component1.IComponent, properties)
local OfferRegistry2 = OpenBusContext2:getOfferRegistry()
OfferRegistry2:registerService(component2.IComponent, properties)

log:TEST("hello service ready!")
