local openbus = require "openbus"
local conn = openbus.connectByAddress("localhost", 2089)
conn:loginByPassword("tester", "tester")

local offer = conn.OfferRegistry:findService({
	{name="openbus.offer.entity",value="Tester"},
	{name="openbus.component.facet",value="hello"},
})
local hello = offer:getFacetByName("hello"):__narrow()


hello:_set_quiet(false)
for i = 1, 3 do print(hello:say_hello_to("world")) end
print("Object already said hello "..hello:_get_count().." times till now.")
