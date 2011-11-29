coroutine = require "coroutine"
cothread = require "cothread"
openbus = require "openbus"
ComponentContext = require "scs.core.ComponentContext"
chain2str = require "chain2str"
memoize = require("loop.table").memoize

-- connect to the bus
conn = openbus.connectByAddress("localhost", 2089)

-- setup ORB
orb = conn.orb
orb:loadidlfile("messages.idl")
cothread.next(coroutine.create(orb.run), orb)

-- setup action on login termination
function conn:onInvalidLogin()
	print("login terminated, shutting the server down")
	conn:close() -- free connection resources
	orb:shutdown() -- stop the ORB and free all its resources
end

-- create service implementation
Messenger = {
	__type = orb.types:lookup("tecgraf::openbus::demo::delegation::Messenger"),
	inboxOf = memoize(function() return {} end),
}
function Messenger:post(to, message)
	local chain = conn:getCallerChain()
	local from = chain[1].entity
	print("post to "..to.." by "..chain2str(chain))
	local inbox = self.inboxOf[to]
	inbox[#inbox+1] = { from=from, message=message }
end
function Messenger:receivePosts()
	local chain = conn:getCallerChain()
	local owner = chain[1].entity
	print("downdoad of messsages by "..chain2str(chain))
	local inbox = self.inboxOf[owner]
	self.inboxOf[owner] = nil
	return inbox
end

-- create service SCS component
component = ComponentContext(orb, {
	name = "Messenger",
	major_version = 1,
	minor_version = 0,
	patch_version = 0,
	platform_spec = "",
})
component:addFacet("messenger", Messenger.__type.repID, Messenger)

-- login to the bus
conn:loginByPassword("messenger", "messenger")

-- offer the service
conn.offers:registerService(component.IComponent, {
	{name="offer.domain",value="OpenBus Demos"}, -- provided property
})
