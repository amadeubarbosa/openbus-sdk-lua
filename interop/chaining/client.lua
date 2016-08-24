local openbus = require "openbus"
local log = require "openbus.util.logger"

local idl = require "openbus.interop.idl"
local loadidl = idl.loadto
local basicidl = require "openbus.interop.idl.basic"
local chainingidl = require "openbus.interop.idl.chaining"

require "openbus.test.util"

-- customize test configuration for this case
settestcfg(...)

-- setup the ORB
local orb = openbus.initORB(orbcfg)

-- load interface definition
loadidl(orb, basicidl)
loadidl(orb, chainingidl)
local iface = orb.types:lookup("tecgraf::openbus::interop::chaining::HelloProxy")

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
