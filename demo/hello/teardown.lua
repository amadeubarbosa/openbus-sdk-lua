local openbus = require "openbus"

-- connect to the bus
local conn = openbus.connectByAddress("localhost", 2089)

-- login to the bus
conn:loginByPassword("admin", "admin")

-- terminate logins
local LoginRegistry = conn.logins
local logins = LoginRegistry:getEntityLogins("demo")
for _, login in ipairs(logins) do
	LoginRegistry:terminateLogin(login.id)
end

-- remove authorizations
local entities = conn.entities
local entity = entities:getEntity("demo")
if entity ~= nil then
	entity:remove()
	local category = entities:getEntityCategory("OpenBusDemos")
	if category ~= nil then
		category:remove()
	end
end

-- remove interface
conn.interfaces:removeInterface("IDL:Hello:1.0")

-- logout from the bus
conn:logout() -- stops the login renewer thread and allow the process to end

-- free connection resources permanently
conn:shutdown()
