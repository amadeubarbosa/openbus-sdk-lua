--require("oil.verbose"):level(2)

local hello = { count = 0, quiet = true }
function hello:say_hello_to(name)
	self.count = self.count + 1
	local msg = "Hello " .. name .. "! ("..self.count.." times)"
	if not self.quiet then print(msg) end
	return msg
end

local openbus = require "openbus"
local conn = openbus.connectByAddress("localhost", 2089)
conn:loginByPassword("tester", "tester")

local orb = conn.orb
orb:loadidl [[
	interface Hello {
		attribute boolean quiet;
		readonly attribute long count;
		string say_hello_to(in string name);
	};
]]
local ComponentContext = require "scs.core.ComponentContext"
local component = ComponentContext(orb, {
	name = "Hello",
	major_version = 1,
	minor_version = 0,
	patch_version = 0,
	platform_spec = "",
})
component:addFacet("hello", "IDL:Hello:1.0", hello)

oil.newthread(orb.run, orb)
conn.OfferRegistry:registerService(component.IComponent, {})
