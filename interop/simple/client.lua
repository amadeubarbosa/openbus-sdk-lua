local openbus = require "openbus"
local log = require "openbus.util.logger"
local util = require "openbus.util.server"

local idl = require "openbus.interop.idl"
local loadidl = idl.loadto
local basicidl = require "openbus.interop.idl.basic"

require "openbus.test.util"

-- customize test configuration for this case
settestcfg(...)

-- setup the ORB
local orb = openbus.initORB(orbcfg)

-- load interface definition
loadidl(orb, basicidl)
local iface = orb.types:lookup("tecgraf::openbus::interop::simple::Hello")

-- get bus context manager
local OpenBusContext = orb.OpenBusContext

-- connect to the bus
busref = assert(util.readfrom(busref, "r"))
busref = orb:newproxy(busref, nil, "::scs::core::IComponent")
local conn = OpenBusContext:connectByReference(busref)
OpenBusContext:setDefaultConnection(conn)

-- login to the bus
conn:loginByPassword(user, password, domain)

-- define service properties
properties[#properties+1] =
  {name="openbus.component.interface",value=iface.repID}

-- find the offered service
log:TEST("retrieve hello service")
local OfferRegistry = OpenBusContext:getOfferRegistry()
for _, offer in ipairs(findoffers(OfferRegistry, properties)) do
  local entity = getprop(offer.properties, "openbus.offer.entity")
  log:TEST("found service of ",entity,"!")
  local hello = offer.service_ref:getFacetByName(iface.name):__narrow(iface)
  local result = hello:sayHello()
  assert(result == "Hello "..user.."!", result)
  log:TEST("test successful for service of ",entity)
end

-- logout from the bus
conn:logout()
orb:shutdown()
