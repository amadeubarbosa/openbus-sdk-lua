--require("oil.verbose"):level(2)

local openbus = require "openbus"
local conn = openbus.connectByAddress("localhost", 2089)
conn:loginByPassword("tester", "tester")

local EntityRegistry = conn.EntityRegistry
local entity = EntityRegistry:getEntity("tester")
if entity == nil then
	local category = EntityRegistry:getEntityCategory("HelloDemo")
	if category == nil then
		category = EntityRegistry:createEntityCategory("HelloDemo", "OpenBus Hello Demo")
	end
	entity = category:registerEntity("tester", "entity used in OpenBus tests and demos")
end
entity:addAuthorization("IDL:Hello:1.0")

conn:logout()
