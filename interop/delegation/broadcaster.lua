local log = require "openbus.util.logger"
local server = require "openbus.util.server"
local openbus = require "openbus"
local ComponentContext = require "scs.core.ComponentContext"
local table = require "loop.table"

require "openbus.test.util"

-- setup and start the ORB
local orb = openbus.initORB()
orb:loadidlfile("messages.idl")
openbus.newthread(orb.run, orb)
local iface = orb.types:lookup("tecgraf::openbus::interop::delegation::Broadcaster")

-- customize test configuration for this case
settestcfg(iface, ...)

-- connect to the bus
local manager = orb.OpenBusConnectionManager
local conn = manager:createConnection(bushost, busport)
manager:setDefaultConnection(conn)

-- create service implementation
Broadcaster = { subscribers = {} }
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
component:addFacet(iface.name, iface.repID, Broadcaster)

-- login to the bus
conn:loginByCertificate(system, assert(server.readfrom(syskey)))

-- define service properties
local iface = orb.types:lookup("tecgraf::openbus::interop::delegation::Messenger")
local props = {{name="openbus.component.interface",value=iface.repID}}

-- retrieve messenger service
log:TEST("retrieve messenger service")
for _, offer in ipairs(findoffers(conn.offers, props)) do
  local entity = getprop(offer.properties, "openbus.offer.entity")
  log:TEST("found messenger service of ",entity,"!")
  Messenger = orb:narrow(offer.service_ref:getFacet(iface.repID), iface)
end

-- offer broadcast service
conn.offers:registerService(component.IComponent, properties)

log:TEST("broadcast service ready!")
