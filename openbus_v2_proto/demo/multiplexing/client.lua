local openbus = require "openbus"

for _, port in ipairs{2089, 2090} do
	
	-- connect to the bus
	local conn = openbus.connectByAddress("localhost", port)
	
	-- login to the bus
	conn:loginByPassword("demo@"..port, "demo@"..port)
	
	-- find the offered services and invoke them
	local offers = conn.offers:findServices({
		{name="openbus.component.facet",value="hello"}, -- automatic property
		{name="offer.domain",value="OpenBus Demos"}, -- provided property
	})
	for _, offer in ipairs(offers) do
		for _, prop in ipairs(offer.properties) do
			if prop.name == "openbus.offer.entity" then
				print("found offer from "..prop.value.." on bus at port "..port)
				break
			end
		end
		local hello = offer.service_ref:getFacetByName("hello"):__narrow()
		hello:sayHello()
	end
	
	-- logout from the bus and free connection resources permanently
	conn:close()
	
end