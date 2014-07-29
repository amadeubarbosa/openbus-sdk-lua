local _G = require "_G"
local ipairs = _G.ipairs
local unpack = _G.unpack

local makeaux = require "openbus.core.idl.makeaux"
local parsed = require "openbus.core.legacy.parsed"



local types, values, throw = {}, {}, {}
for _, parsed in ipairs(parsed) do
  if parsed.name == "tecgraf" then
    makeaux(parsed, types, values, throw)
  end
end

local idl = {
  types = types.tecgraf.openbus.core.v1_05,
  values = values.tecgraf.openbus.core.v1_05,
  throw = throw.tecgraf.openbus.core.v1_05,
  typesFT = types.tecgraf.openbus.fault_tolerance.v1_05,
}

function idl.loadto(orb)
  orb.TypeRepository.registry:register(unpack(parsed))
end

return idl
