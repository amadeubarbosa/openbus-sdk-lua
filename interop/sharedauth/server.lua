local log = require "openbus.util.logger"
local server = require "openbus.util.server"
local openbus = require "openbus"
local ComponentContext = require "scs.core.ComponentContext"

require "openbus.test.util"

-- setup and start the ORB
local orb = openbus.initORB()
orb:loadidlfile("hello.idl")
openbus.newthread(orb.run, orb)
local iface = orb.types:lookup("tecgraf::openbus::interop::simple::Hello")

-- customize test configuration for this case
settestcfg(iface, ...)

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
component:addFacet(iface.name, iface.repID, hello)

-- login to the bus
conn:loginByCertificate(system, assert(server.readfrom(syskey)))

-- offer service
conn.offers:registerService(component.IComponent, properties)

log:TEST("hello service ready!")

local attempt, secret = conn:startSharedAuth()

orb:loadidlfile("encoding.idl")
local idltype = orb.types:lookup("tecgraf::openbus::interop::sharedauth::EncodedSharedAuth")
local encoder = orb:newencoder()
encoder:put({attempt=attempt,secret=secret}, idltype)
assert(oil.writeto("sharedauth.dat", encoder:getdata(), "wb"))

log:TEST("shared authentication data written to file!")
