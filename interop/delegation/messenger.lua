local log = require "openbus.util.logger"
local openbus = require "openbus"
local ComponentContext = require "scs.core.ComponentContext"
local chain2str = require "chain2str"
local table = require "loop.table"

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
local Messenger = {
  __type = orb.types:lookup("tecgraf::openbus::interop::delegation::Messenger"),
  inboxOf = table.memoize(function() return {} end),
}
function Messenger:post(to, message)
  local chain = conn:getCallerChain()
  local from = chain2str(chain)
  log:TEST("post to ",to," by ",from)
  local inbox = self.inboxOf[to]
  inbox[#inbox+1] = { from=from, message=message }
end
function Messenger:receivePosts()
  local chain = conn:getCallerChain()
  local owner = (chain.originators[1] or chain.caller).entity
  log:TEST("downdoad of messsages of ",owner," by ",chain2str(chain))
  local inbox = self.inboxOf[owner]
  self.inboxOf[owner] = nil
  return inbox
end

-- create service SCS component
local component = ComponentContext(orb, {
  name = "Messenger",
  major_version = 1,
  minor_version = 0,
  patch_version = 0,
  platform_spec = "",
})
component:addFacet("messenger", Messenger.__type.repID, Messenger)

-- login to the bus
conn:loginByCertificate("messenger", syskey)

-- offer messenger service
conn.offers:registerService(component.IComponent, {
  {name="offer.domain",value="Interoperability Tests"}, -- provided property
})

log:TEST("messenger service ready!")
