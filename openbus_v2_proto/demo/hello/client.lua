local openbus = require "openbus"

-- connect to the bus
local conn = openbus.connectByAddress("localhost", 2089)

-- login to the bus
conn:loginByPassword("HelloCaller", "HelloCaller")

-- find the offered service
local offers = conn.OfferRegistry:findServices({
	{name="openbus.offer.entity",value="HelloServer"}, -- automatic property
	{name="openbus.component.facet",value="hello"}, -- automatic property
	{name="offer.domain",value="OpenBus Demos"}, -- provided property
})
assert(#offers > 0, "unable to find offered service")
local hello = offers[1].service_ref:getFacetByName("hello"):__narrow()

-- call the service
hello:sayHello()

-- logout from the bus
conn:logout() -- stops the login renewer thread and allow the process to end

-- free connection resources permanently
conn:shutdown()
