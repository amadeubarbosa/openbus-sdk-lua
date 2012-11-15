local _G = require "_G"
local assert = _G.assert
local error = _G.error
local getmetatable = _G.getmetatable
local ipairs = _G.ipairs
local pairs = _G.pairs
local select = _G.select
local tonumber = _G.tonumber
local tostring = _G.tostring
local type = _G.type

local array = require "table"
local insert = array.insert



local function checktype(funcname, index, typenames, value)
  local luatype = type(value)
  for typename in typenames:gmatch("[^|]+") do
    if typename == "string" and luatype == "number" then
      value = tostring(value)
    elseif typename == "number" and luatype == "string" then
      value = tonumber(value) or value
    end
    if luatype == typename then
      return value
    end
  end
  error("bad argument #"..index.." to '"..funcname.."' (expected "..typenames
      ..", got "..luatype..")", 3)
end

local function checkmeta(funcname, index, expected, value)
  local actual = getmetatable(value)
  if actual == expected then
    return value
  end
  error("bad argument #"..index.." to '"..funcname
      .."' (expected object, got "..type(value)..")", 3)
end

local function convertmodule(module, typedefs)
  for name, typedef in pairs(typedefs) do
    local func = module[name]
    assert(type(func) == "function", name.." was not a function (got "..type(func)..")")
    module[name] = function(...)
      for index, typename in ipairs(typedef) do
        local checker = (type(typename)=="string") and checktype or checkmeta
        checker(name, index, typename, select(index, ...))
      end
      return func(...)
    end
  end
end



local argcheck = {
  checktype = checktype,
  checkmeta = checkmeta,
  convertmodule = convertmodule,
}

function argcheck.convertclass(class, typedefs)
  for name, typedef in pairs(typedefs) do
    insert(typedef, 1, class)
  end
  return convertmodule(class, typedefs)
end

return argcheck
