local openbus = require "openbus"

-- create ORBs
local orb1 = openbus.createORB()
local orb2 = openbus.createORB()

-- connect to the bus
local conn1 = openbus.connectByAddress("localhost", 2089, orb1)
local conn2 = openbus.connectByAddress("localhost", 2089, orb2)

-- login to the bus using password
conn1:loginByPassword("demo", "demo")

-- login to the bus using single sign-on
local logger, secret = conn1:startSingleSignOn()
conn2:loginBySingleSignOn(logger, secret)

-- find the offered service
for _, conn in ipairs{conn1, conn2} do
	local offers = conn.offers:findServices({
		{name="openbus.offer.entity",value="demo"}, -- automatic property
		{name="openbus.component.facet",value="hello"}, -- automatic property
		{name="offer.domain",value="OpenBus Demos"}, -- provided property
	})
	assert(#offers > 0, "unable to find offered service")
	for _, offer in ipairs(offers) do
		local hello = offer.service_ref:getFacetByName("hello"):__narrow()
		hello:sayHello()
	end
	conn:close()
end
