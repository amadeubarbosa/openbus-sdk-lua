local log = require "openbus.util.logger"
local openbus = require "openbus"

bushost, busport, verbose = ...
require "openbus.util.testcfg"

-- setup the ORB
local orb = openbus.initORB()
orb:loadidlfile("encoding.idl")
orb:loadidlfile("hello.idl")

-- connect to the bus
local manager = orb.OpenBusConnectionManager
local conn = manager:createConnection(bushost, busport)
manager:setDefaultConnection(conn)

-- find the offered service
log:TEST(true, "retrieve shared authentication data")
local attempt, secret
local tries = 10
for i = 1, tries do
  local data = oil.readfrom("sharedauth.dat", "rb")
  if data ~= nil then
    os.remove("sharedauth.dat")
    local idltype = orb.types:lookup("tecgraf::openbus::interop::sharedauth::EncodedSharedAuth")
    local sharedauth = orb:newdecoder(data):get(idltype)
    attempt, secret = orb:narrow(sharedauth.attempt), sharedauth.secret
    break
  end
  log:TEST("shared authentication data not found yet (try ",i," of ",tries,")")
  openbus.sleep(1)
end
log:TEST(false, "shared authentication data found!")

conn:loginBySharedAuth(attempt, secret)
assert(conn.login.entity == system)

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
      assert(hello:sayHello() == "Hello "..system.."!")
      conn:logout()
      return log:TEST("test successful")
    end
  end
  log:TEST("hello service not found yet (try ",i," of ",tries,")")
  openbus.sleep(1)
end
