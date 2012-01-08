local coroutine = require "coroutine"
local cothread = require "cothread"
local openbus = require "openbus"
local ComponentContext = require "scs.core.ComponentContext"

-- connect to the bus
local conn = openbus.connectByAddress("localhost", 2089)

-- setup and start the ORB
local orb = conn.orb
orb:loadidl "interface Hello { void sayHello(); };"
cothread.next(coroutine.create(orb.run), orb)

-- setup action on login termination
function conn:onInvalidLogin()
	print("login terminated, shutting the server down")
	conn:close() -- free connection resources
	orb:shutdown() -- stop the ORB and free all its resources
end

-- create service implementation
local hello = {}
function hello:sayHello()
	local callers = conn:getCallerChain().callers
	print("Hello from "..callers[1].entity.."!")
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
conn:loginByPassword("demo", "demo")

-- offer the service
conn.offers:registerService(component.IComponent, {
	{name="offer.domain",value="OpenBus Demos"}, -- provided property
})
