local openbus = require "openbus"

-- connect to the bus
local conn = openbus.connectByAddress("localhost", 2089)

-- login to the bus
conn:loginByPassword("admin", "admin")

-- add interface
conn.interfaces:registerInterface("IDL:Hello:1.0")

-- add authorizations
local entities = conn.entities
local entity = entities:getEntity("demo")
if entity == nil then
  local category = entities:getEntityCategory("OpenBusDemos")
  if category == nil then
    category = entities:createEntityCategory("OpenBusDemos", "OpenBus Demo Entities")
  end
  entity = category:registerEntity("demo", "entity used in OpenBus demos")
end
entity:grantInterface("IDL:Hello:1.0")

-- logout from the bus and free connection resources permanently
conn:close()
