local _G = require "_G"
local assert = _G.assert
local error = _G.error
local ipairs = _G.ipairs

local Exception = require "loop.object.Exception"

local function makeaux(def, types, consts, excepts)
	local name = def.name
	if def._type == "module" then
		local definitions = def.definitions
		if definitions ~= nil then
			for _, def in ipairs(definitions) do
				types[name] = types[name] or {}
				excepts[name] = excepts[name] or {}
				consts[name] = consts[name] or {}
				makeaux(def, types[name], consts[name], excepts[name])
			end
		end
	elseif def._type == "except" then
		local repID = def.repID
		types[name] = repID
		excepts[name] = function(fields)
			if fields == nil then fields = {} end
			fields._repid = repID
			error(Exception(fields))
		end
	elseif def._type == "const" then
		consts[name] = def.value 
	elseif name ~= nil then
		types[name] = def.repID
	end
end

return makeaux