local log = require "openbus.util.logger"
local openbus = require "openbus"

require "openbus.test.util"

-- setup the ORB
local orb = openbus.initORB()
orb:loadidlfile("hello.idl")
local iface = orb.types:lookup("tecgraf::openbus::interop::simple::Hello")

-- customize test configuration for this case
settestcfg(iface, ...)

-- connect to the bus
local manager = orb.OpenBusConnectionManager
local conn = manager:createConnection(bushost, busport)
manager:setDefaultConnection(conn)

-- find the offered service
log:TEST("retrieve shared authentication data")
orb:loadidlfile("encoding.idl")
local idltype = orb.types:lookup("tecgraf::openbus::interop::sharedauth::EncodedSharedAuth")
local sharedauth = orb:newdecoder(waitfile("sharedauth.dat")):get(idltype)
attempt, secret = orb:narrow(sharedauth.attempt), sharedauth.secret

-- login to the bus
conn:loginBySharedAuth(attempt, secret)

-- define service properties
local props = {{name="openbus.component.interface",value=iface.repID}}

-- find the offered service
log:TEST("retrieve hello service")
for _, offer in ipairs(findoffers(conn.offers, props)) do
  local entity = getprop(offer.properties, "openbus.offer.entity")
  log:TEST("found service of ",entity,"!")
  local hello = offer.service_ref:getFacetByName(iface.name):__narrow(iface)
  local result = hello:sayHello()
  assert(result == "Hello "..conn.login.entity.."!", result)
  log:TEST("test successful for service of ",entity)
end

conn:logout()
