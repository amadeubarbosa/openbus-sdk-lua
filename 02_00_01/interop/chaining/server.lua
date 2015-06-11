local openbus = require "openbus"
local log = require "openbus.util.logger"
local sysex = require "openbus.util.sysex"
local ComponentContext = require "scs.core.ComponentContext"

require "openbus.test.util"

-- customize test configuration for this case
settestcfg(...)

-- setup and start the ORB
local orb = openbus.initORB(orbcfg)

-- load interface definition
orb:loadidlfile("helloidl/hello.idl")
local iface = orb.types:lookup("tecgraf::openbus::interop::simple::Hello")

-- get bus context manager
local OpenBusContext = orb.OpenBusContext

-- create service implementation
local hello = {}
local expected = {
  cpp = true,
  java = true,
  lua = true,
  csharp = true,
}
function hello:sayHello()
  local chain = OpenBusContext:getCallerChain()
  local entity = chain.caller.entity
  if expected[entity:match("^interop_chaining_(.-)_proxy$")] ~= nil then
    log:TEST("got call from ",chain2str(chain))
    return "Hello "..chain.originators[1].entity.."!"
  else
    sysex.NO_PERMISSION()
  end
end

-- create service SCS component
local component = ComponentContext(orb, {
  name = "RestrictedHello",
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
