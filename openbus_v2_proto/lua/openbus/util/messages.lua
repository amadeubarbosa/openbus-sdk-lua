local _G = require "_G"
local setmetatable = _G.setmetatable

local oilverbose = require "oil.verbose"
local viewer = oilverbose.viewer

local oo = require "openbus.util.oo"
local class = oo.class

local function toword(camelcase)
	return camelcase:lower().." "
end

local MissingMessage = class()
function MissingMessage:tag(values)
	return self:__tostring()..viewer:tostring(values)
end
function MissingMessage:__tostring()
	return self.message:gsub("%u[%l%d]*", toword)
end

return setmetatable({}, {
	__index = function(_, message)
		return MissingMessage{ message = message }
	end,
})
