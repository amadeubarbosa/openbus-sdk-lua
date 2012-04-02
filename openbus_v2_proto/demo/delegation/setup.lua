local openbus = require "openbus"

-- connect to the bus
local conn = openbus.connect("localhost", 2089)

-- login to the bus
conn:loginByPassword("admin", "admin")

-- add interfaces and authorizations
local interfaces = conn.interfaces
local entities = conn.entities
local category = entities:getEntityCategory("OpenBusDemos")
if category == nil then
  category = entities:createEntityCategory("OpenBusDemos", "OpenBus Demo Entities")
end
for _, name in ipairs{"Messenger","Broadcaster","Forwarder"} do
  local ifaceId = "IDL:tecgraf/openbus/demo/delegation/"..name..":1.0"
  interfaces:registerInterface(ifaceId)
  local entityId = name:lower()
  local entity = entities:getEntity(entityId)
  if entity == nil then
    entity = category:registerEntity(entityId, "entity used in OpenBus demos")
  end
  entity:grantInterface(ifaceId)
end

-- logout from the bus and free connection resources permanently
conn:close()
