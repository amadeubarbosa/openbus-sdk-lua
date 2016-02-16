local _G = require "_G"

local array = require "table"
local unpack = array.unpack or _G.unpack

local idl = {}

function idl.loadto(orb, parsed)
  orb.TypeRepository.registry:register(unpack(parsed))
end

return idl