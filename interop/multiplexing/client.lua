local openbus = require "openbus"
local log = require "openbus.util.logger"
local util = require "openbus.util.server"
local table = require "loop.table"

require "openbus.test.util"

-- customize test configuration for this case
settestcfg(...)

-- setup and start the ORB
local orb = openbus.initORB(orbcfg)
orb:loadidlfile("idl/hello.idl")

-- load interface definition
local iface = orb.types:lookup("tecgraf::openbus::interop::simple::Hello")

-- get bus context manager
local OpenBusContext = orb.OpenBusContext

-- define service properties
properties[#properties+1] = 
  {name="openbus.component.interface",value=iface.repID}

busref = assert(util.readfrom(busref, "r"))
bus2ref = assert(util.readfrom(bus2ref, "r"))
for _, businfo in ipairs{
  {ref=orb:newproxy(busref, nil, "::scs::core::IComponent"), offers=3},
  {ref=orb:newproxy(bus2ref, nil, "::scs::core::IComponent"), offers=1},
} do
  -- connect to the bus
  local conn = OpenBusContext:connectByReference(businfo.ref)
  OpenBusContext:setDefaultConnection(conn)
  
  -- login to the bus
  conn:loginByPassword(user, password, domain)
  
  -- find the offered service
  log:TEST("retrieve hello services from bus ",conn.busid,"!")
  local expected = businfo.offers
  local services = table.memoize(function() return {} end)
  local OfferRegistry = OpenBusContext:getOfferRegistry()
  for _, offer in ipairs(findoffers(OfferRegistry, properties, expected)) do
    local entity = getprop(offer.properties, "openbus.offer.entity")
    local login = getprop(offer.properties, "openbus.offer.login")
    log:TEST("found service of ",entity,"! (",login,")")
    assert(services[entity][login] == nil)
    services[entity][login] =
      offer.service_ref:getFacetByName(iface.name):__narrow(iface)
  end
  
  log:TEST("invoking services from bus ",conn.busid,"!")
  for entity, services in pairs(services) do
    local count = 0
    for login, hello in pairs(services) do
      assert(hello:sayHello() == "Hello "..user.."@"..conn.busid.."!")
      count = count+1
    end
    assert(count == expected, entity..": found "..count.." of "..expected)
  end
  
  -- logout from the bus
  conn:logout()
end

orb:shutdown()
