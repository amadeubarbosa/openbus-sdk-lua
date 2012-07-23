local log = require "openbus.util.logger"
local openbus = require "openbus"
local ComponentContext = require "scs.core.ComponentContext"
local chain2str = require "chain2str"

bushost, busport, verbose = ...
require "openbus.util.testcfg"

-- setup and start the ORB
local orb = openbus.initORB()
orb:loadidlfile("messages.idl")
openbus.newthread(orb.run, orb)

-- connect to the bus
local manager = orb.OpenBusConnectionManager
local conn = manager:createConnection(bushost, busport)
manager:setDefaultConnection(conn)

-- create service implementation
Broadcaster = {
  __type = orb.types:lookup("tecgraf::openbus::interop::delegation::Broadcaster"),
  subscribers = {},
}
function Broadcaster:post(message)
  conn:joinChain() -- joins the current caller chain
  for user in pairs(self.subscribers) do
    Messenger:post(user, message)
  end
end
function Broadcaster:subscribe()
  local chain = conn:getCallerChain()
  local user = chain.caller.entity
  log:TEST("subscription by ",chain2str(chain))
  self.subscribers[user] = true
end
function Broadcaster:unsubscribe()
  local chain = conn:getCallerChain()
  local user = chain.caller.entity
  log:TEST("unsubscription by ",chain2str(chain))
  self.subscribers[user] = nil
end

-- create service SCS component
local component = ComponentContext(orb, {
  name = "Broadcaster",
  major_version = 1,
  minor_version = 0,
  patch_version = 0,
  platform_spec = "",
})
component:addFacet("broadcaster", Broadcaster.__type.repID, Broadcaster)

local msgIface = orb.types:lookup("tecgraf::openbus::interop::delegation::Messenger")

-- login to the bus
conn:loginByCertificate("broadcaster", syskey)

-- retrieve messenger service
log:TEST(true, "retrieve messenger service")
Messenger = nil
repeat
  offers = conn.offers:findServices({
    {name="openbus.offer.entity",value="messenger"}, -- automatic property
    {name="openbus.component.interface",value=msgIface.repID}, -- automatic property
    {name="offer.domain",value="Interoperability Tests"}, -- provided property
  })
  for _, offer in ipairs(offers) do
    local service = offer.service_ref
    if not service:_non_existent() then
      Messenger = orb:narrow(service:getFacet(msgIface.repID), msgIface)
      break
    end
  end
  if Messenger then break end
  log:TEST("mesenger service not found yet...")
  openbus.sleep(1)
until false
log:TEST(false, "messenger service found!")

-- offer broadcast service
conn.offers:registerService(component.IComponent, {
  {name="offer.domain",value="Interoperability Tests"}, -- provided property
})

log:TEST("broadcast service ready!")
