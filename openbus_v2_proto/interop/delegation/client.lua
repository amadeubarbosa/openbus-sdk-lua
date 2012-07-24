local log = require "openbus.util.logger"
local openbus = require "openbus"
local ComponentContext = require "scs.core.ComponentContext"

bushost, busport, verbose = ...
require "openbus.util.testcfg"

-- setup and start the ORB
local orb = openbus.initORB()
orb:loadidlfile("messages.idl")

-- connect to the bus
local manager = orb.OpenBusConnectionManager
local conn = manager:createConnection(bushost, busport)
manager:setDefaultConnection(conn)

-- login to the bus
conn:loginByPassword(user, password)

-- find the offered services
log:TEST(true, "retrieve required services")
local tries = 10
for i = 1, tries do
  offers = conn.offers:findServices({
    {name="offer.domain",value="Interoperability Tests"}, -- provided property
  })
  for _, offer in ipairs(offers) do
    local service = offer.service_ref
    if not service:_non_existent() then
      local name, iface
      for _, prop in ipairs(offer.properties) do
        if prop.name == "openbus.component.facet" then
          assert(name == nil)
          name = prop.value
        elseif prop.name == "openbus.component.interface" then
          assert(iface == nil)
          iface = prop.value
        end
      end
      _G[name] = orb:narrow(service:getFacet(iface), iface)
    end
  end
  if messenger == nil or broadcaster == nil or forwarder == nil then
    log:TEST("not all service found after ",i,(" seconds "):tag{
      messenger = messenger~=nil and "OK" or nil,
      broadcaster = broadcaster~=nil and "OK" or nil,
      forwarder = forwarder~=nil and "OK" or nil,
    })
    openbus.sleep(1)
  else
    break
  end
end
log:TEST(false, "required services found!")

-- logout from the bus
conn:logout()

conn:loginByPassword("bill", "bill")
forwarder:setForward("willian")
broadcaster:subscribe()
conn:logout()

conn:loginByPassword("paul", "paul")
broadcaster:subscribe()
conn:logout()

conn:loginByPassword("mary", "mary")
broadcaster:subscribe()
conn:logout()

conn:loginByPassword("steve", "steve")
broadcaster:subscribe()
broadcaster:post("Testing the list!")
conn:logout()

log:TEST("waiting for messages to propagate")
for i = 1, 10 do openbus.sleep(1) end

local function showPostsOf(user, posts)
  log:TEST(true, user," received ",#posts," messages:")
  for index, post in ipairs(posts) do
    log:TEST(index,") ",post.from,": ",post.message)
  end
  log:TEST(false)
end

local expected = {
  willian = {
    {
      from = "forwarder",
      message = "forwared message by broadcaster:steve: Testing the list!",
    },
    n = 1,
  },
  bill = {
    n = 0,
  },
  paul = {
    {
      from = "broadcaster:steve",
      message = "Testing the list!",
    },
    n = 1,
  },
  mary = {
    {
      from = "broadcaster:steve",
      message = "Testing the list!",
    },
    n = 1,
  },
  steve = {
    {
      from = "broadcaster:steve",
      message = "Testing the list!",
    },
    n = 1,
  },
}
local actual = {}
for _, user in ipairs{"willian", "bill", "paul", "mary", "steve"} do
  conn:loginByPassword(user, user)
  actual[user] = messenger:receivePosts()
  log:TEST(user," got posts: ",actual[user])
  broadcaster:unsubscribe()
  conn:logout()
end

conn:loginByPassword("bill", "bill")
forwarder:cancelForward("willian")
conn:logout()


assert(require("loop.debug.Matcher"){metatable=false}:match(actual, expected))
