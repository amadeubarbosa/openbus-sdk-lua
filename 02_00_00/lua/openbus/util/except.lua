local table = require "loop.table"
local copy = table.copy

local giop = require "oil.corba.giop"
local sysex = giop.SystemExceptionIDs

local core = require "openbus.core.idl"
local lib = require "openbus.idl"

local function getexrepid(repid, module, ...)
  local throw, types = module.throw, module.types
  for i = 1, select("#", ...) do
    local key = select(i, ...)
    throw = throw[key]
    types = types[key]
  end
  for name in pairs(throw) do
    assert(repid[name] == nil)
    repid[name] = types[name]
  end
end

local repid = copy(sysex)

getexrepid(repid, lib)
getexrepid(repid, core, "services")
getexrepid(repid, core, "services", "access_control")
getexrepid(repid, core, "services", "offer_registry")

local minor = {}
for field, value in pairs(core.const.services.access_control) do
  local name = field:match("^(%w+)Code$")
  if name ~= nil then
    minor[name] = value
  end
end

return {
  repid = repid,
  minor = minor,
}
