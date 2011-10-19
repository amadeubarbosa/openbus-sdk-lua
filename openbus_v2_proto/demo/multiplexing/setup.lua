function registerEntity(conn, name)
	local entities = conn.entities
	local entity = entities:getEntity(name)
	if entity == nil then
		local category = entities:getEntityCategory("OpenBusDemos")
		if category == nil then
			category = entities:createEntityCategory("OpenBusDemos", "OpenBus Demo Entities")
		end
		entity = category:registerEntity(name, "entity used in OpenBus demos")
	end
	entity:grantInterface("IDL:Hello:1.0")
end

local openbus = require "openbus"

do
	-- connect to the bus
	local conn = openbus.connectByAddress("localhost", 2089)
	
	-- login to the bus
	conn:loginByPassword("admin", "admin")
	
	-- add interface
	conn.interfaces:registerInterface("IDL:Hello:1.0")
	
	-- add authorizations
	registerEntity(conn, "demo")
	registerEntity(conn, "conn1")
	registerEntity(conn, "conn2")
	
	-- logout from the bus and free connection resources permanently
	conn:close()
end

do
	-- connect to the bus
	local conn = openbus.connectByAddress("localhost", 2090)
	
	-- login to the bus
	conn:loginByPassword("admin", "admin")
	
	-- add interface
	conn.interfaces:registerInterface("IDL:Hello:1.0")
	
	-- add authorizations
	registerEntity(conn, "demo")
	
	-- logout from the bus and free connection resources permanently
	conn:close()
end
