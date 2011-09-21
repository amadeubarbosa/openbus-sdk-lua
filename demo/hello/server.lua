local coroutine = require "coroutine"
local cothread = require "cothread"
local openbus = require "openbus"

-- create service implementation
local hello = { count = 0, quiet = true }
function hello:say_hello_to(name)
	self.count = self.count + 1
	local msg = "Hello " .. name .. "! ("..self.count.." times)"
	if not self.quiet then print(msg) end
	return msg
end

-- setup ORB
local orb = openbus.initORB()
orb:loadidl [[
	interface Hello {
		attribute boolean quiet;
		readonly attribute long count;
		string say_hello_to(in string name);
	};
]]
cothread.next(coroutine.create(orb.run), orb)

-- create service SCS component
local ComponentContext = require "scs.core.ComponentContext"
local component = ComponentContext(orb, {
	name = "Hello",
	major_version = 1,
	minor_version = 0,
	patch_version = 0,
	platform_spec = "",
})
component:addFacet("hello", "IDL:Hello:1.0", hello)

-- connect to the bus, login as 'hello' and offer the service
local conn = openbus.connectByAddress("localhost", 2089)
function conn:onExpiration()
	assert(not self:isLogged())
	self:loginByPassword("tester", "tester")
	self.OfferRegistry:registerService(component.IComponent, {
		{name="offer.domain",value="OpenBus Demos"},
	})
end
conn:onExpiration()
