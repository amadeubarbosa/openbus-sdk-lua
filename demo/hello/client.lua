local openbus = require "openbus"
local conn = openbus.connectByAddress("localhost", 2089)
conn:loginByPassword("tester", "tester")

local offers = conn.OfferRegistry:findServices({
	{name="openbus.offer.entity",value="tester"},
	{name="openbus.component.facet",value="hello"},
})
assert(#offers > 0, "unable to find offered service")
local hello = offers[1].service_ref:getFacetByName("hello"):__narrow()

hello:_set_quiet(false)
for i = 1, 3 do print(hello:say_hello_to("world")) end
print("Object already said hello "..hello:_get_count().." times till now.")

conn:logout()
