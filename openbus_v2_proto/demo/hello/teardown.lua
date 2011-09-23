local openbus = require "openbus"

-- connect to the bus
local conn = openbus.connectByAddress("localhost", 2089)

-- login to the bus
conn:loginByPassword("admin", "admin")

-- remove offer authorizations
local EntityRegistry = conn.EntityRegistry
local entity = EntityRegistry:getEntity("HelloServer")
if entity ~= nil then
	entity:remove()
	local category = EntityRegistry:getEntityCategory("HelloDemo")
	if category ~= nil then
		category:remove()
	end
end

-- terminate logins
local LoginRegistry = conn.LoginRegistry
local logins = LoginRegistry:getEntityLogins("HelloServer")
for _, login in ipairs(logins) do
	LoginRegistry:terminateLogin(login.id)
end

-- logout from the bus
conn:logout() -- stops the login renewer thread and allow the process to end

-- free connection resources permanently
conn:shutdown()
