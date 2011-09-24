local openbus = require "openbus"

-- connect to the bus
local conn = openbus.connectByAddress("localhost", 2089)

-- login to the bus
conn:loginByPassword("admin", "admin")

-- add offer authorizations
local offAuths = conn.offAuths
local category = offAuths:getEntityCategory("OpenBusDemos")
if category == nil then
	category = offAuths:createEntityCategory("OpenBusDemos", "OpenBus Demo Entities")
end
for _, name in ipairs{"Messenger","Broadcaster","Forwarder"} do
	local entityId = name:lower()
	local entity = offAuths:getEntity(entityId)
	if entity == nil then
		entity = category:registerEntity(entityId, "entity used in OpenBus demos")
	end
	entity:addAuthorization("IDL:tecgraf/openbus/demo/delegation/"..name..":1.0")
end

-- logout from the bus
conn:logout() -- stops the login renewer thread and allow the process to end

-- free connection resources permanently
conn:shutdown()
