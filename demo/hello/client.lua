local openbus = require "openbus"

-- connect to the bus
local conn = openbus.connectByAddress("localhost", 2089)

-- login to the bus
conn:loginByPassword("demo", "demo")

-- find the offered service
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
