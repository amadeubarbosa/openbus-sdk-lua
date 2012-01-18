local _G = require "_G"
local rawget = _G.rawget
local select = _G.select

local table = require "loop.table"
local memoize = table.memoize

local function create(weakmode)
	return memoize(create, weakmode)
end

local function remove(table, key, ...)
	if select("#", ...) == 0 then
		local value = table[key]
		table[key] = nil
		return value
	else
		local value = rawget(table, key)
		if value ~= nil then
			return remove(value, ...)
		end
	end
end

return {
	create = create,
	remove = remove,
}
