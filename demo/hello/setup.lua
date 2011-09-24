local openbus = require "openbus"

-- connect to the bus
local conn = openbus.connectByAddress("localhost", 2089)

-- login to the bus
conn:loginByPassword("admin", "admin")

-- add offer authorizations
local offAuths = conn.offAuths
local entity = offAuths:getEntity("demo")
if entity == nil then
	local category = offAuths:getEntityCategory("OpenBusDemos")
	if category == nil then
		category = offAuths:createEntityCategory("OpenBusDemos", "OpenBus Demo Entities")
	end
	entity = category:registerEntity("demo", "entity used in OpenBus demos")
end
entity:addAuthorization("IDL:Hello:1.0")

-- logout from the bus
conn:logout() -- stops the login renewer thread and allow the process to end

-- free connection resources permanently
conn:shutdown()
