local openbus = require "openbus"
local log = require "openbus.util.logger"
local util = require "openbus.util.server"

local idl = require "openbus.interop.idl"
local loadidl = idl.loadto
local delegationidl = require "openbus.interop.idl.delegation"

require "openbus.test.util"

-- customize test configuration for this case
settestcfg(...)

-- setup and start the ORB
local orb = openbus.initORB(orbcfg)

-- load interface definition
loadidl(orb, delegationidl)
local iface = orb.types:lookup("tecgraf::openbus::interop::delegation::Messenger")

-- get bus context manager
local OpenBusContext = orb.OpenBusContext

-- connect to the bus
busref = assert(util.readfrom(busref, "r"))
busref = orb:newproxy(busref, nil, "::scs::core::IComponent")
local conn = OpenBusContext:connectByReference(busref)
OpenBusContext:setDefaultConnection(conn)

-- login to the bus
conn:loginByPassword(user, password, domain)

-- retrieve services
local OfferRegistry = OpenBusContext:getOfferRegistry()
local services = {}
for _, name in ipairs{"Messenger", "Broadcaster", "Forwarder"} do
  -- define service properties
  local iface = orb.types:lookup("tecgraf::openbus::interop::delegation::"..name)
  local props = { table.unpack(properties),
    {name="openbus.component.interface",value=iface.repID},
  }
  -- retrieve service
  log:TEST("retrieve messenger service")
  for _, offer in ipairs(findoffers(OfferRegistry, props)) do
    local entity = getprop(offer.properties, "openbus.offer.entity")
    log:TEST("found messenger service of ",entity,"!")
    services[name] = {
      entity = entity,
      ref = orb:narrow(offer.service_ref:getFacet(iface.repID), iface),
    }
  end
end



-- logout from the bus
conn:logout()

conn:loginByPassword("bill", "bill", domain)
services.Forwarder.ref:setForward("willian")
services.Broadcaster.ref:subscribe()
conn:logout()

conn:loginByPassword("paul", "paul", domain)
services.Broadcaster.ref:subscribe()
conn:logout()

conn:loginByPassword("mary", "mary", domain)
services.Broadcaster.ref:subscribe()
conn:logout()

conn:loginByPassword("steve", "steve", domain)
services.Broadcaster.ref:subscribe()
services.Broadcaster.ref:post("Testing the list!")
conn:logout()

log:TEST("waiting for messages to propagate")
openbus.sleep(leasetime)

local expected = {
  willian = {
    {
      from = services.Forwarder.entity,
      message = "forwarded message by steve->"..services.Broadcaster.entity..": Testing the list!",
    },
    n = 1,
  },
  bill = {
    n = 0,
  },
  paul = {
    {
      from = "steve->"..services.Broadcaster.entity,
      message = "Testing the list!",
    },
    n = 1,
  },
  mary = {
    {
      from = "steve->"..services.Broadcaster.entity,
      message = "Testing the list!",
    },
    n = 1,
  },
  steve = {
    {
      from = "steve->"..services.Broadcaster.entity,
      message = "Testing the list!",
    },
    n = 1,
  },
}
local actual = {}
for _, user in ipairs{"willian", "bill", "paul", "mary", "steve"} do
  conn:loginByPassword(user, user, domain)
  actual[user] = services.Messenger.ref:receivePosts()
  log:TEST(user," got posts: ",actual[user])
  services.Broadcaster.ref:unsubscribe()
  conn:logout()
end

conn:loginByPassword("bill", "bill", domain)
services.Forwarder.ref:cancelForward("willian")
conn:logout()
orb:shutdown()

assert(require("loop.debug.Matcher"){metatable=false}:match(actual, expected))
