local openbus = require "openbus"
local log = require "openbus.util.logger"
local util = require "openbus.util.server"

require "openbus.test.util"

-- customize test configuration for this case
settestcfg(...)

-- setup the ORB
local orb = openbus.initORB(orbcfg)

-- load interface definition
orb:loadidlfile("idl/proxy.idl")
local iface = orb.types:lookup("tecgraf::openbus::interop::chaining::HelloProxy")

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
  local entity = getprop(offer.properties, "openbus.offer.entity")
  local chain = OpenBusContext:makeChainFor(entity)
  local encoded = OpenBusContext:encodeChain(chain)
  local result = hello:fetchHello(encoded)
  assert(result == "Hello "..user.."!", result)
  log:TEST("test successful for service of ",entity)
end

-- logout from the bus
conn:logout()
orb:shutdown()
