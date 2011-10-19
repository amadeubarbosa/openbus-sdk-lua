local table = require "loop.table"
local memoize = table.memoize

local function toword(camelcase)
	return camelcase:lower().." "
end

return memoize(function(message)
	return message:gsub("%u[%l%d]*", toword)
end)
