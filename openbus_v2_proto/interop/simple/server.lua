local log = require "openbus.util.logger"
local openbus = require "openbus"
local ComponentContext = require "scs.core.ComponentContext"

bushost, busport, verbose = ...
require "openbus.util.testcfg"

-- setup and start the ORB
local orb = openbus.initORB()
orb:loadidlfile("hello.idl")
openbus.newthread(orb.run, orb)

-- connect to the bus
local manager = orb.OpenBusConnectionManager
local conn = manager:createConnection(bushost, busport)
manager:setDefaultConnection(conn)

-- create service implementation
local hello = {}
function hello:sayHello()
  return "Hello "..conn:getCallerChain().caller.entity.."!"
end

-- create service SCS component
local component = ComponentContext(orb, {
  name = "Hello",
  major_version = 1,
  minor_version = 0,
  patch_version = 0,
  platform_spec = "Lua",
})
local iface = "tecgraf::openbus::interop::simple::Hello"
component:addFacet("Hello", orb.types:lookup(iface).repID, hello)

-- login to the bus
conn:loginByCertificate(system, syskey)

-- offer service
conn.offers:registerService(component.IComponent, {
  {name="offer.domain",value="Interoperability Tests"}, -- provided property
})

log:TEST("hello service ready!")
