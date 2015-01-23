local openbus = require "openbus"
local log = require "openbus.util.logger"
local util = require "openbus.util.server"

require "openbus.test.util"

-- customize test configuration for this case
settestcfg(...)

-- setup the ORB
local orb = openbus.initORB(orbcfg)

-- load interface definition
orb:loadidlfile("idl/hello.idl")
local iface = orb.types:lookup("tecgraf::openbus::interop::simple::Hello")

-- get bus context manager
local OpenBusContext = orb.OpenBusContext

-- connect to the bus
busref = assert(util.readfrom(busref, "r"))
busref = orb:newproxy(busref, nil, "::scs::core::IComponent")
local conn = OpenBusContext:connectByReference(busref)
OpenBusContext:setDefaultConnection(conn)

-- read shared authentication data
log:TEST("retrieve shared authentication data")
local secret = OpenBusContext:decodeSharedAuth(waitfile(sharedauthfile, 100, .1))

-- login to the bus
conn:loginBySharedAuth(secret)

-- define service properties
local props = {{name="openbus.component.interface",value=iface.repID}}

-- find the offered service
log:TEST("retrieve hello service")
local OfferRegistry = OpenBusContext:getOfferRegistry()
for _, offer in ipairs(findoffers(OfferRegistry, props)) do
  local entity = getprop(offer.properties, "openbus.offer.entity")
  log:TEST("found service of ",entity,"!")
  local hello = offer.service_ref:getFacetByName(iface.name):__narrow(iface)
  local result = hello:sayHello()
  assert(result == "Hello "..conn.login.entity.."!", result)
  log:TEST("test successful for service of ",entity)
end

-- logout from the bus
conn:logout()
orb:shutdown()
