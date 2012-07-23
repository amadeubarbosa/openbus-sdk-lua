local log = require "openbus.util.logger"
local openbus = require "openbus"
local ComponentContext = require "scs.core.ComponentContext"
local table = require "loop.table"
local Timer = require "cothread.Timer"
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
Forwarder = {
  __type = orb.types:lookup("tecgraf::openbus::interop::delegation::Forwarder"),
  forwardsOf = {},
}
function Forwarder:setForward(to)
  local chain = conn:getCallerChain()
  local user = chain.caller.entity
  log:TEST("setup forward to ",to," by ",chain2str(chain))
  self.forwardsOf[user] = {chain=chain, to=to}
end
function Forwarder:cancelForward()
  local chain = conn:getCallerChain()
  local user = chain.caller.entity
  local forward = self.forwardsOf[user]
  if forward ~= nil then
    log:TEST("cancel forward to ",forward.to," by ",chain2str(chain))
    self.forwardsOf[user] = nil
  end
end
function Forwarder:getForward()
  local chain = conn:getCallerChain()
  local user = chain.caller.entity
  local forward = self.forwardsOf[user]
  if forward == nil then
    error(orb:newexcept{"tecgraf::openbus::interop::delegation::NoForward"})
  end
  return forward.to
end

-- create timer to forward messages from time to time
timer = Timer{ rate = 5 }
function timer:action()
  for user, forward in pairs(Forwarder.forwardsOf) do
    local to = forward.to
    log:TEST("checking messages of ",to)
    conn:joinChain(forward.chain)
    local posts = Messenger:receivePosts()
    conn:exitChain()
    for _, post in ipairs(posts) do
      Messenger:post(to, "forwared from "..post.from..": "..post.message)
    end
  end
end
timer:enable()

-- create service SCS component
component = ComponentContext(orb, {
  name = "Forwarder",
  major_version = 1,
  minor_version = 0,
  patch_version = 0,
  platform_spec = "",
})
component:addFacet("forwarder", Forwarder.__type.repID, Forwarder)

local msgIface = orb.types:lookup("tecgraf::openbus::interop::delegation::Messenger")

-- login to the bus
conn:loginByCertificate("forwarder", syskey)

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

log:TEST("forwarder service ready!")
