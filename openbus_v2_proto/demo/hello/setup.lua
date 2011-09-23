local openbus = require "openbus"

-- connect to the bus
local conn = openbus.connectByAddress("localhost", 2089)

-- login to the bus
conn:loginByPassword("admin", "admin")

-- add offer authorizations
local EntityRegistry = conn.EntityRegistry
local entity = EntityRegistry:getEntity("HelloServer")
if entity == nil then
	local category = EntityRegistry:getEntityCategory("HelloDemo")
	if category == nil then
		category = EntityRegistry:createEntityCategory("HelloDemo", "OpenBus Hello Demo")
	end
	entity = category:registerEntity("HelloServer", "entity used in OpenBus tests and demos")
end
entity:addAuthorization("IDL:Hello:1.0")

-- logout from the bus
conn:logout() -- stops the login renewer thread and allow the process to end

-- free connection resources permanently
conn:shutdown()
