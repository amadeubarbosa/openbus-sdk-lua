local openbus = require "openbus"
local log = require "openbus.util.logger"
local ComponentContext = require "scs.core.ComponentContext"
local table = require "loop.table"

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
local iface = orb.types:lookup("tecgraf::openbus::interop::delegation::Messenger")

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
