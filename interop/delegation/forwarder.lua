local openbus = require "openbus"
local log = require "openbus.util.logger"
local util = require "openbus.util.server"
local ComponentContext = require "scs.core.ComponentContext"
local table = require "loop.table"
local Timer = require "cothread.Timer"

local idl = require "openbus.interop.idl"
local loadidl = idl.loadto
local delegationidl = require "openbus.interop.idl.delegation"

require "openbus.test.util"

-- customize test configuration for this case
settestcfg(...)

-- setup and start the ORB
local orb = openbus.initORB(orbcfg)

-- load interface definitions
loadidl(orb, delegationidl)
local iface = orb.types:lookup("tecgraf::openbus::interop::delegation::Forwarder")

-- get bus context manager
local OpenBusContext = orb.OpenBusContext

-- create service implementation
Forwarder = { forwardsOf = {} }
function Forwarder:setForward(to)
  local chain = OpenBusContext:getCallerChain()
  local user = chain.caller.entity
  log:TEST("setup forward to ",to," by ",chain2str(chain))
  self.forwardsOf[user] = {chain=chain, to=to}
end
function Forwarder:cancelForward()
  local chain = OpenBusContext:getCallerChain()
  local user = chain.caller.entity
  local forward = self.forwardsOf[user]
  if forward ~= nil then
    log:TEST("cancel forward to ",forward.to," by ",chain2str(chain))
    self.forwardsOf[user] = nil
  end
end
function Forwarder:getForward()
  local chain = OpenBusContext:getCallerChain()
  local user = chain.caller.entity
  local forward = self.forwardsOf[user]
  if forward == nil then
    error(orb:newexcept{"tecgraf::openbus::interop::delegation::NoForward"})
  end
  return forward.to
end

-- create timer to forward messages from time to time
timer = Timer{ rate = leasetime/2 }
function timer:action()
  for user, forward in pairs(Forwarder.forwardsOf) do
    log:TEST("checking messages of ",user)
    OpenBusContext:joinChain(forward.chain)
    local posts = Messenger:receivePosts()
    OpenBusContext:exitChain()
    for _, post in ipairs(posts) do
      Messenger:post(forward.to, "forwarded message by "..post.from..": "..post.message)
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
component:addFacet(iface.name, iface.repID, Forwarder)

-- connect to the bus
busref = assert(util.readfrom(busref, "r"))
busref = orb:newproxy(busref, nil, "::scs::core::IComponent")
local conn = OpenBusContext:connectByReference(busref)
OpenBusContext:setDefaultConnection(conn)

-- login to the bus
conn:loginByCertificate(system, assert(openbus.readKeyFile(syskey)))

-- define service properties
local iface = orb.types:lookup("tecgraf::openbus::interop::delegation::Messenger")
local props = {{name="openbus.component.interface",value=iface.repID}}

-- retrieve messenger service
log:TEST("retrieve messenger service")
local OfferRegistry = OpenBusContext:getOfferRegistry()
for _, offer in ipairs(findoffers(OfferRegistry, props)) do
  local entity = getprop(offer.properties, "openbus.offer.entity")
  log:TEST("found messenger service of ",entity,"!")
  Messenger = orb:narrow(offer.service_ref:getFacet(iface.repID), iface)
end

-- offer broadcast service
OfferRegistry:registerService(component.IComponent, properties)

log:TEST("forwarder service ready!")
