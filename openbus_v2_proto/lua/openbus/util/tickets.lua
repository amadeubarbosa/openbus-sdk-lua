local math = require "math"
local min = math.min

local array = require "table"
local concat = array.concat

local oo = require "openbus.util.oo"
local class = oo.class

local function discardBase(self, size, base, index)
	for i = 1, size do
		if self[index] == nil then break end
		self[index] = nil
		index = (index+1)%size
		base = base+1
	end
	self.base = base
	self.index = (index+1)%size
end

local TicketHistory = class{
	base = 0,
	index = 0,
	size = 32,
}

function TicketHistory:__tostring()
	local size = self.size
	local base = self.base
	local index = self.index
	local str = { "{ " }
	for i = 0, size-1 do
		str[#str+1] = (i == index) and "..."..base.." " or " "
		if i >= index then
			str[#str+1] = self[i] and "_" or base+i-index+1
		else
			str[#str+1] = self[i] and "_" or base+size-index+i+1
		end
	end
	str[#str+1] = " }"
	return concat(str)
end

function TicketHistory:check(id)
	local size = self.size
	local base = self.base
	local index = self.index
	if id < base then
		return false
	elseif id == base then
		discardBase(self, size, base+1, index)
		return true
	else -- id > base
		local shift = id-base-1
		if shift < size then
			index = (index+shift)%size
			if self[index] == true then return false end
			self[index] = true
			return true
		else
			local extra = shift-size
			for i = 1, min(extra, size) do
				self[index] = nil
				index = (index+1)%size
			end
			discardBase(self, size, base+extra+1, index)
			return self:check(id)
		end
	end
end

return TicketHistory
