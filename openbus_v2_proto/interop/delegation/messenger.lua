local log = require "openbus.util.logger"
local openbus = require "openbus"
local ComponentContext = require "scs.core.ComponentContext"
local table = require "loop.table"

require "openbus.test.util"

-- setup and start the ORB
local orb = openbus.initORB()
openbus.newThread(orb.run, orb)

-- load interface definitions
orb:loadidlfile("messages.idl")
local iface = orb.types:lookup("tecgraf::openbus::interop::delegation::Messenger")

-- customize test configuration for this case
settestcfg(iface, ...)

-- get bus context manager
local OpenBusContext = orb.OpenBusContext

-- create service implementation
local Messenger = { inboxOf = table.memoize(function() return {} end) }
function Messenger:post(to, message)
  local chain = OpenBusContext:getCallerChain()
  local from = chain2str(chain)
  log:TEST("post to ",to," by ",from)
  local inbox = self.inboxOf[to]
  inbox[#inbox+1] = { from=from, message=message }
end
function Messenger:receivePosts()
  local chain = OpenBusContext:getCallerChain()
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
component:addFacet(iface.name, iface.repID, Messenger)

-- connect to the bus
local conn = OpenBusContext:createConnection(bushost, busport)
OpenBusContext:setDefaultConnection(conn)

-- login to the bus
conn:loginByCertificate(system, assert(openbus.readKeyFile(syskey)))

-- offer messenger service
local OfferRegistry = OpenBusContext:getOfferRegistry()
OfferRegistry:registerService(component.IComponent, properties)

log:TEST("messenger service ready!")
