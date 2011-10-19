local openbus = require "openbus"

for _, port in ipairs{2089, 2090} do
	
	-- connect to the bus
	local conn = openbus.connectByAddress("localhost", port)
	
	-- login to the bus
	conn:loginByPassword("admin", "admin")
	
	-- terminate logins
	local LoginRegistry = conn.logins
	for _, entity in ipairs{"conn1","conn2","demo"} do
		local logins = LoginRegistry:getEntityLogins(entity)
		for _, login in ipairs(logins) do
			LoginRegistry:terminateLogin(login.id)
		end
	end
	
	-- remove the whole category
	local category = conn.entities:getEntityCategory("OpenBusDemos")
	if category ~= nil then
		category:removeAll()
	end
	
	-- remove interface
	conn.interfaces:removeInterface("IDL:Hello:1.0")
	
	-- logout from the bus and free connection resources permanently
	conn:close()
	
end

