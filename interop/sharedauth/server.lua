local log = require "openbus.util.logger"
local openbus = require "openbus"
local ComponentContext = require "scs.core.ComponentContext"
local oil = require "oil"

require "openbus.test.util"

-- setup and start the ORB
local orb = openbus.initORB()

-- load interface definition
orb:loadidlfile("idl/hello/hello.idl")
local iface = orb.types:lookup("tecgraf::openbus::interop::simple::Hello")

-- customize test configuration for this case
settestcfg(iface, ...)

-- get bus context manager
local OpenBusContext = orb.OpenBusContext

-- create service implementation
local hello = {}
function hello:sayHello()
  local entity = OpenBusContext:getCallerChain().caller.entity
  log:TEST("got call from ",entity)
  return "Hello "..entity.."!"
end

-- create service SCS component
local component = ComponentContext(orb, {
  name = "Hello",
  major_version = 1,
  minor_version = 0,
  patch_version = 0,
  platform_spec = "Lua",
})
component:addFacet(iface.name, iface.repID, hello)

-- connect to the bus
local conn = OpenBusContext:createConnection(bushost, busport)
OpenBusContext:setDefaultConnection(conn)

-- login to the bus
conn:loginByCertificate(system, assert(openbus.readKeyFile(syskey)))

-- offer service
local OfferRegistry = OpenBusContext:getOfferRegistry()
OfferRegistry:registerService(component.IComponent, properties)

log:TEST("hello service ready!")

-- serialize shared authentication data
local secret = conn:startSharedAuth()
local encoded = OpenBusContext:encodeSharedAuth(secret)
assert(oil.writeto("sharedauth.dat", encoded, "wb"))

log:TEST("shared authentication data written to file!")
