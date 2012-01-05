local _G = require "_G"
local pairs = _G.pairs
local tostring = _G.tostring

local string = require "string"

local array = require "table"
local concat = array.concat

local table = require "loop.table"
local memoize = table.memoize

local Viewer = require "loop.debug.Viewer"
local viewer = Viewer{ newline="", identation="", maxdepth=2 }

function string:tag(values)
	if self:match(' $') then
		local fields = {}
		local i = 0
		for name, value in pairs(values) do
			i = i+1
			fields[i] = name..'=$'..name
		end
		self = self..'('..concat(fields, ';')..')'
	end
	return (self:gsub(
		'(%$+)([_%a][_%w]*)',
		function(prefix, field)
			local size = #prefix
			if size%2 == 1 then
				field = viewer:tostring(values[field])
			end
			return prefix:sub(1, size/2)..field
		end
	))
end

local function toword(camelcase)
	return camelcase:lower().." "
end

return memoize(function(message)
	return message:gsub("%u[%l%d]*", toword)
end)
