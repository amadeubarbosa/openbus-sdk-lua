local coroutine = require "coroutine"
local cothread = require "cothread"
local openbus = require "openbus"
local ComponentContext = require "scs.core.ComponentContext"

-- connect to the bus
local conn = openbus.connectByAddress("localhost", 2089)

-- create service implementation
local hello = {}
function hello:sayHello()
	local chain = conn:getCallerChain()
	print("Hello from "..chain[1].entity.."!")
end

-- setup ORB
local orb = conn.orb
orb:loadidl "interface Hello { void sayHello(); };"
cothread.next(coroutine.create(orb.run), orb)

-- setup action on login termination
function conn:onLoginTerminated()
	print("OpenBus login terminated, shuting down the server")
	conn:shutdown() -- free connection resources permanently
	orb:shutdown() -- stops the ORB and frees all its resources
end

-- create service SCS component
local component = ComponentContext(orb, {
	name = "Hello",
	major_version = 1,
	minor_version = 0,
	patch_version = 0,
	platform_spec = "",
})
component:addFacet("hello", orb.types:lookup("Hello").repID, hello)

-- login to the bus
conn:loginByPassword("HelloServer", "HelloServer")

-- offer the service
conn.OfferRegistry:registerService(component.IComponent, {
	{name="offer.domain",value="OpenBus Demos"}, -- provided property
})
