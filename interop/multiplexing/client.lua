local log = require "openbus.util.logger"
local openbus = require "openbus"

bushost, busport, verbose = ...
require "openbus.util.testcfg"

-- setup and start the ORB
local orb = openbus.initORB()
orb:loadidlfile("hello.idl")

-- connect to the bus
local manager = orb.OpenBusConnectionManager

for _, businfo in ipairs{
  {host=bushost, port=busport, offers=3},
  {host=bus2host, port=bus2port, offers=1},
} do
  
  -- connect to the bus
  local conn = manager:createConnection(businfo.host, businfo.port)
  manager:setDefaultConnection(conn)
  
  -- login to the bus
  conn:loginByPassword(user, password)
  
  -- retrieve required services
  log:TEST(true, "retrieve required services from bus ",conn.busid)
  local services = {}
  local tries = 10
  for i = 1, tries do
    local offers = conn.offers:findServices({
      {name="openbus.component.facet",value="Hello"}, -- automatic property
      {name="offer.domain",value="Interoperability Tests"}, -- provided property
    })
    local count = 0
    for _, offer in ipairs(offers) do
      local service = offer.service_ref
      if not service:_non_existent() then
        for _, prop in ipairs(offer.properties) do
          if prop.name == "openbus.offer.login" then
            local login = prop.value
            assert(services[login] == nil)
            services[login] = service:getFacetByName("Hello"):__narrow()
            count = count+1
            break
          end
        end
      end
    end
    if count < businfo.offers then
      log:TEST(count," services found after ",i," seconds, ",businfo.offers-count," missing")
      openbus.sleep(1)
    else
      break
    end
  end
  log:TEST(false, "required services found at bus ",conn.busid,"!")
  
  log:TEST("invoking ",businfo.offers," services from bus ",conn.busid,"!")
  for login, hello in pairs(services) do
    assert(hello:sayHello() == "Hello from "..user.."@"..conn.busid.."!")
  end
  
  -- logout from the bus
  conn:logout()
end
