local openbus = require "openbus"

-- connect to the bus
local conn = openbus.connectByAddress("localhost", 2089)

-- login to the bus
conn:loginByPassword("admin", "admin")

-- remove the whole category
local category = conn.entities:getEntityCategory("OpenBusDemos")
if category ~= nil then
	category:removeAll()
end

-- remove interfaces
local interfaces = conn.interfaces
for _, name in ipairs{"Messenger","Broadcaster","Forwarder"} do
	local ifaceId = "IDL:tecgraf/openbus/demo/delegation/"..name..":1.0"
	interfaces:removeInterface(ifaceId)
end

-- terminate logins
local entities = {
	messenger = true,
	broadcaster = true,
	forwarder = true,
	willian = true,
	bill = true,
	paul = true,
	mary = true,
	steve = true,
}
local logins = conn.logins
for entity in pairs(entities) do
	for _, login in ipairs(logins:getEntityLogins(entity)) do
		logins:terminateLogin(login.id)
	end
end


-- logout from the bus
conn:logout() -- stops the login renewer thread and allow the process to end

-- free connection resources permanently
conn:shutdown()
