local _G = require "_G"
local assert = _G.assert
local ipairs = _G.ipairs
local pairs = _G.pairs
local pcall = _G.pcall
local select = _G.select

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



local module = {
  repid = repid,
  minor = minor,
}

function module.refStatus(object)
  local ok, result = pcall(object._non_existent, object)
  if ok then
    if not result then
      return "accessible"
    end
    return "nonexistent"
  end
  if result._repid == sysex.TRANSIENT then
    return "unreachable", result
  end
  return "failure", result
end

function module.newSearchProps(entity, facet)
  return {
    {name="openbus.offer.entity",value=entity},
    {name="openbus.component.facet",value=facet},
  }
end

function module.getProperty(properties, name)
  for _, prop in ipairs(properties) do
    if prop.name == name then
      return prop.value
    end
  end
end

return module