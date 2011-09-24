coroutine = require "coroutine"
cothread = require "cothread"
openbus = require "openbus"
ComponentContext = require "scs.core.ComponentContext"
chain2str = require "chain2str"
Timer = require "cothread.Timer"
memoize = require("loop.table").memoize

-- connect to the bus
conn = openbus.connectByAddress("localhost", 2089)

-- setup ORB
orb = conn.orb
orb:loadidlfile("messages.idl")
cothread.next(coroutine.create(orb.run), orb)

-- create service implementation
Forwarder = {
	__type = orb.types:lookup("tecgraf::openbus::demo::delegation::Forwarder"),
	forwardsOf = memoize(function() return {} end),
}
function Forwarder:addForward(to)
	local chain = conn:getCallerChain()
	local user = chain[1].entity
	print("setup forward to "..to.." by "..chain2str(chain))
	self.forwardsOf[user][to] = chain
end
function Forwarder:removeForward(to)
	local chain = conn:getCallerChain()
	local user = chain[1].entity
	print("cancel forward to "..to.." by "..chain2str(chain))
	self.forwardsOf[user][to] = nil
end
function Forwarder:getMyForwards()
	local chain = conn:getCallerChain()
	local user = chain[1].entity
	local forwards = self.forwardsOf[user]
	local result = {}
	for to in pairs(forwards) do
		result[#result+1] = to
	end
	return result
end

-- create timer to forward messages from time to time
timer = Timer{ rate = 5 }
function timer:action()
	for user, forwards in pairs(Forwarder.forwardsOf) do
		for to, chain in pairs(forwards) do
			print("checking messages of "..to)
			conn:joinChain(chain)
			local posts = Messenger:receivePosts()
			conn:exitChain()
			for _, post in ipairs(posts) do
				Messenger:post(to, "forwared from "..post.from..": "..post.message)
			end
		end
	end
end
timer:enable()

-- setup action on login termination
function conn:onLoginTerminated()
	print("login terminated, shuting the server down")
	timer:disable() -- stop the timer
	conn:shutdown() -- free connection resources
	orb:shutdown() -- stop the ORB and free all its resources
end

-- create service SCS component
component = ComponentContext(orb, {
	name = "Forwarder",
	major_version = 1,
	minor_version = 0,
	patch_version = 0,
	platform_spec = "",
})
component:addFacet("forwarder", Forwarder.__type.repID, Forwarder)

-- login to the bus
conn:loginByPassword("forwarder", "forwarder")

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
