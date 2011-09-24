local openbus = require "openbus"

-- connect to the bus
local conn = openbus.connectByAddress("localhost", 2089)

-- login to the bus
conn:loginByPassword("admin", "admin")

-- remove offer authorizations
local offAuths = conn.offAuths
local entity = offAuths:getEntity("demo")
if entity ~= nil then
	entity:remove()
	local category = offAuths:getEntityCategory("OpenBusDemos")
	if category ~= nil then
		category:remove()
	end
end

-- terminate logins
local LoginRegistry = conn.logins
local logins = LoginRegistry:getEntityLogins("demo")
for _, login in ipairs(logins) do
	LoginRegistry:terminateLogin(login.id)
end

-- logout from the bus
conn:logout() -- stops the login renewer thread and allow the process to end

-- free connection resources permanently
conn:shutdown()
