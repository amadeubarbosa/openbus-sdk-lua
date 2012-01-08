coroutine = require "coroutine"
cothread = require "cothread"
openbus = require "openbus"
ComponentContext = require "scs.core.ComponentContext"
chain2str = require "chain2str"

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
Broadcaster = {
	__type = orb.types:lookup("tecgraf::openbus::demo::delegation::Broadcaster"),
	subscribers = {},
}
function Broadcaster:post(message)
	conn:joinChain() -- joins the current caller chain
	for user in pairs(self.subscribers) do
		Messenger:post(user, message)
	end
end
function Broadcaster:subscribe()
	local callers = conn:getCallerChain().callers
	local user = callers[1].entity
	print("subscription by "..chain2str(callers))
	self.subscribers[user] = true
end
function Broadcaster:unsubscribe()
	local callers = conn:getCallerChain().callers
	local user = callers[1].entity
	print("unsubscription by "..chain2str(callers))
	self.subscribers[user] = nil
end

-- create service SCS component
component = ComponentContext(orb, {
	name = "Broadcaster",
	major_version = 1,
	minor_version = 0,
	patch_version = 0,
	platform_spec = "",
})
component:addFacet("broadcaster", Broadcaster.__type.repID, Broadcaster)

-- login to the bus
conn:loginByPassword("broadcaster", "broadcaster")

-- find messenger
offers = conn.offers:findServices({
	{name="openbus.offer.entity",value="messenger"}, -- automatic property
	{name="openbus.component.facet",value="messenger"}, -- automatic property
	{name="offer.domain",value="OpenBus Demos"}, -- provided property
})
assert(#offers > 0, "unable to find offered service")
Messenger = orb:narrow(offers[1].service_ref:getFacetByName("messenger"),
                       "tecgraf::openbus::demo::delegation::Messenger")

-- offer the service
conn.offers:registerService(component.IComponent, {
	{name="offer.domain",value="OpenBus Demos"}, -- provided property
})
