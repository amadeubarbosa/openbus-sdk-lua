local openbus = require "openbus"
local log = require "openbus.util.logger"
local ComponentContext = require "scs.core.ComponentContext"
local oil = require "oil"

require "openbus.test.util"

-- customize test configuration for this case
settestcfg(...)

-- setup and start the ORB
local orb = openbus.initORB(orbcfg)

-- load interface definition
orb:loadidlfile("idl/hello/hello.idl")
local iface = orb.types:lookup("tecgraf::openbus::interop::simple::Hello")

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

-- generate shared authentication data
local attempt, secret = conn:startSharedAuth()

-- load interface definition
orb:loadidlfile("idl/sharedauth/encoding.idl")
local idltype = orb.types:lookup("tecgraf::openbus::interop::sharedauth::EncodedSharedAuth")

-- serialize shared authentication data
local encoder = orb:newencoder()
encoder:put({attempt=attempt,secret=secret}, idltype)
assert(oil.writeto("sharedauth.dat", encoder:getdata(), "wb"))

log:TEST("shared authentication data written to file!")
