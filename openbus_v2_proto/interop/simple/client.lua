local log = require "openbus.util.logger"
local openbus = require "openbus"

bushost, busport, verbose = ...
require "openbus.util.testcfg"

-- setup the ORB
local orb = openbus.initORB()
orb:loadidlfile("hello.idl")
local repid = orb.types:lookup("tecgraf::openbus::interop::simple::Hello").repID

-- connect to the bus
local manager = orb.OpenBusConnectionManager
local conn = manager:createConnection(bushost, busport)
manager:setDefaultConnection(conn)

-- login to the bus
conn:loginByPassword(user, password)

-- define service properties
local props = {
  {name="openbus.component.interface",value=repid},
  {name="offer.domain",value="Interoperability Tests"},
}

local function findProp(properties, name)
  for _, prop in ipairs(properties) do
    if prop.name == name then return prop.value end
  end
end

-- find the offered service
log:TEST("retrieve hello service")
local tries = 10
for i = 1, tries do
  local found
  local offers = conn.offers:findServices(props)
  for _, offer in ipairs(offers) do
    local entity = findProp(offer.properties, "openbus.offer.entity")
    local service = offer.service_ref
    if not service:_non_existent() then
      log:TEST("found service of ",entity,"!")
      found = true
      local hello = service:getFacetByName("Hello"):__narrow(repid)
      assert(hello:sayHello() == "Hello "..user.."!",
        "wrong result from service of "..entity)
      log:TEST("test successful for service of ",entity)
    end
  end
  if found then break end
  log:TEST("hello service not found yet (try ",i," of ",tries,")")
  openbus.sleep(1)
end
conn:logout()
