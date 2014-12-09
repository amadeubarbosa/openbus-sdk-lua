local openbus = require "openbus"
local log = require "openbus.util.logger"
local util = require "openbus.util.server"
local ComponentContext = require "scs.core.ComponentContext"
local table = require "loop.table"

require "openbus.test.util"

-- customize test configuration for this case
settestcfg(...)

-- setup and start the ORB
local orb = openbus.initORB(orbcfg)

-- load interface definition
orb:loadidlfile("idl/hello.idl")
local iface = orb.types:lookup("tecgraf::openbus::interop::simple::Hello")

-- get bus context manager
local OpenBusContext = orb.OpenBusContext

-- create service implementation
local hello = {}
function hello:sayHello()
	local chain = OpenBusContext:getCallerChain()
	local entity = chain.caller.entity
	local originators = chain.originators
	if #originators > 0 then
		entity = originators[1].entity
	end
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
busref = assert(util.readfrom(busref, "r"))
busref = orb:newproxy(busref, nil, "::scs::core::IComponent")
local conn = OpenBusContext:connectByReference(busref)
OpenBusContext:setDefaultConnection(conn)

-- login to the bus
conn:loginByCertificate(system, assert(openbus.readKeyFile(syskey)))

-- define service properties
local servprops = table.copy(properties)
servprops[#servprops+1] =
  {name="reloggedjoin.role",value="server"}

-- offer service
local OfferRegistry = OpenBusContext:getOfferRegistry()
OfferRegistry:registerService(component.IComponent, servprops)

log:TEST("hello service ready!")
