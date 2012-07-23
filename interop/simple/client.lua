local log = require "openbus.util.logger"
local openbus = require "openbus"

bushost, busport, verbose = ...
require "openbus.util.testcfg"

-- login to the bus
local manager = openbus.initORB().OpenBusConnectionManager
local conn = manager:createConnection(bushost, busport)
conn:loginByPassword(user, password)
manager:setDefaultConnection(conn)

-- define service properties
local props = {
  {name="openbus.offer.entity",value=system},
  {name="openbus.component.facet",value="Hello"},
  {name="offer.domain",value="Interoperability Tests"},
}

-- find the offered service
log:TEST(true, "retrieve hello service")
local tries = 10
for i = 1, tries do
  local offers = conn.offers:findServices(props)
  for _, offer in ipairs(offers) do
    local service = offer.service_ref
    if not service:_non_existent() then
      log:TEST(false, "hello service found!")
      local hello = service:getFacetByName("Hello"):__narrow()
      assert(hello:sayHello() == "Hello "..user.."!")
      conn:logout()
      return log:TEST("test successful")
    end
  end
  log:TEST("hello service not found yet (try ",i," of ",tries,")")
  openbus.sleep(1)
end
