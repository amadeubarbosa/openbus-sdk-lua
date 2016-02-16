local openbus = require "openbus"
local log = require "openbus.util.logger"
local util = require "openbus.util.server"
local ComponentContext = require "scs.core.ComponentContext"
local table = require "loop.table"

local idl = require "openbus.interop.idl"
local loadidl = idl.loadto
local basicidl = require "openbus.interop.idl.basic"

require "openbus.test.util"

-- customize test configuration for this case
settestcfg(...)

-- setup and start the ORB
local orb = openbus.initORB(orbcfg)

-- load interface definition
loadidl(orb, basicidl)
local iface = orb.types:lookup("tecgraf::openbus::interop::simple::Hello")

-- read login private key
local key = assert(openbus.readKeyFile(syskey))

-- get bus context manager
local OpenBusContext = orb.OpenBusContext

-- create service implementation
local hello = {}
function hello:sayHello()
  local conn = OpenBusContext:getCurrentConnection()
  log:TEST("relogging entity ",system)
  conn:logout()
  conn:loginByCertificate(system, key)
  local chain = OpenBusContext:getCallerChain()
  local entity = chain.caller.entity
  log:TEST("got call from ",entity)
  
  -- define service properties
  local searchprops = table.copy(properties)
  searchprops[#searchprops+1] =
    {name="reloggedjoin.role",value="server"}

  -- find the offered service
  log:TEST("retrieve hello service")
  local OfferRegistry = OpenBusContext:getOfferRegistry()
  for _, offer in ipairs(findoffers(OfferRegistry, searchprops)) do
    local entity = getprop(offer.properties, "openbus.offer.entity")
    log:TEST("found service of ",entity,"!")
    local hello = offer.service_ref:getFacetByName(iface.name):__narrow(iface)
    OpenBusContext:joinChain(chain)
    return hello:sayHello()
  end
  return "no service found!"
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
conn:loginByCertificate(system, key)

-- define service properties
local servprops = table.copy(properties)
servprops[#servprops+1] =
  {name="reloggedjoin.role",value="proxy"}

-- offer service
local OfferRegistry = OpenBusContext:getOfferRegistry()
OfferRegistry:registerService(component.IComponent, servprops)

log:TEST("hello service proxy ready!")
