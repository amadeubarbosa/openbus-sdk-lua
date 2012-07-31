local log = require "openbus.util.logger"
local openbus = require "openbus"

require "openbus.test.util"

-- setup and start the ORB
local orb = openbus.initORB()
orb:loadidlfile("messages.idl")
local iface = orb.types:lookup("tecgraf::openbus::interop::delegation::Messenger")

-- customize test configuration for this case
settestcfg(iface, ...)

-- connect to the bus
local manager = orb.OpenBusConnectionManager
local conn = manager:createConnection(bushost, busport)
manager:setDefaultConnection(conn)

-- login to the bus
conn:loginByPassword(user, password)

-- retrieve services
local services = {}
for _, name in ipairs{"Messenger", "Broadcaster", "Forwarder"} do
  -- define service properties
  local iface = orb.types:lookup("tecgraf::openbus::interop::delegation::"..name)
  local props = { unpack(properties),
    {name="openbus.component.interface",value=iface.repID},
  }
  -- retrieve service
  log:TEST("retrieve messenger service")
  for _, offer in ipairs(findoffers(conn.offers, props)) do
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

conn:loginByPassword("bill", "bill")
services.Forwarder.ref:setForward("willian")
services.Broadcaster.ref:subscribe()
conn:logout()

conn:loginByPassword("paul", "paul")
services.Broadcaster.ref:subscribe()
conn:logout()

conn:loginByPassword("mary", "mary")
services.Broadcaster.ref:subscribe()
conn:logout()

conn:loginByPassword("steve", "steve")
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
  conn:loginByPassword(user, user)
  actual[user] = services.Messenger.ref:receivePosts()
  log:TEST(user," got posts: ",actual[user])
  services.Broadcaster.ref:unsubscribe()
  conn:logout()
end

conn:loginByPassword("bill", "bill")
services.Forwarder.ref:cancelForward("willian")
conn:logout()

assert(require("loop.debug.Matcher"){metatable=false}:match(actual, expected))
