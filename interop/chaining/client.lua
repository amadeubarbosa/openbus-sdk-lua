local log = require "openbus.util.logger"
local openbus = require "openbus"

require "openbus.test.util"

-- setup the ORB
local orb = openbus.initORB()

-- load interface definition
orb:loadidlfile("idl/proxy.idl")
local iface = orb.types:lookup("tecgraf::openbus::interop::chaining::HelloProxy")

-- customize test configuration for this case
settestcfg(iface, ...)

-- get bus context manager
local OpenBusContext = orb.OpenBusContext

-- connect to the bus
local conn = OpenBusContext:createConnection(bushost, busport)
OpenBusContext:setDefaultConnection(conn)

-- login to the bus
conn:loginByPassword(user, password)

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
  local login = getprop(offer.properties, "openbus.offer.login")
  local chain = OpenBusContext:makeChainFor(login)
  local encoded = OpenBusContext:encodeChain(chain)
  local result = hello:fetchHello(encoded)
  assert(result == "Hello "..user.."!", result)
  log:TEST("test successful for service of ",entity)
end

-- logout from the bus
conn:logout()
orb:shutdown()