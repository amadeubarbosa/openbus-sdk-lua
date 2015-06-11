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
orb:loadidlfile("idl/proxy.idl")
orb:loadidlfile("helloidl/hello.idl")
local iface = orb.types:lookup("tecgraf::openbus::interop::chaining::HelloProxy")
local serviface = orb.types:lookup("tecgraf::openbus::interop::simple::Hello")

-- get bus context manager
local OpenBusContext = orb.OpenBusContext

-- create service implementation
local hello = {}
function hello:fetchHello(encodedChain)
  local ok, ex = pcall(function ()
    local chain = OpenBusContext:decodeChain(encodedChain)
    OpenBusContext:joinChain(chain)
  end)
  if not ok then
    print(ex)
    sysex.BAD_PARAM()
  end

  local result

  local ok, ex = pcall(function ()
    -- define service properties
    properties[#properties+1] =
      {name="openbus.component.interface",value=serviface.repID}
    properties[#properties+1] =
      {name="openbus.component.name",value="RestrictedHello"},
    
    -- find the offered service
    log:TEST("retrieve hello service")
    local OfferRegistry = OpenBusContext:getOfferRegistry()
    for _, offer in ipairs(findoffers(OfferRegistry, properties)) do
      local entity = getprop(offer.properties, "openbus.offer.entity")
      log:TEST("found service of ",entity,"!")
      local hello = offer.service_ref:getFacetByName(serviface.name):__narrow(serviface)
      result = hello:sayHello()
      log:TEST("got result from service of ",entity)
      break
    end
  end)
  if not ok then
    print(ex)
    sysex.NO_RESOURCES()
  end

  return result
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
