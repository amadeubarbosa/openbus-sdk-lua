local _G = require "_G"
local assert = _G.assert
local error = _G.error
local ipairs = _G.ipairs
local type = _G.type

local array = require "table"
local concat = array.concat

local Exception = require "oil.corba.giop.Exception"

local log = require "openbus.util.logger"
local msg = require "openbus.util.messages"

local function makeaux(def, types, consts, excepts)
  local name = def.name
  if def._type == "module" then
    local definitions = def.definitions
    if definitions ~= nil then
      for _, def in ipairs(definitions) do
        types[name] = types[name] or {}
        excepts[name] = excepts[name] or {}
        consts[name] = consts[name] or {}
        makeaux(def, types[name], consts[name], excepts[name])
      end
    end
  elseif def._type == "except" then
    local message = def.absolute_name
    local members = def.members
    if #members > 0 then
      local fields = {}
      for index, member in ipairs(members) do
        local name = member.name
        fields[index] = name..": $"..name
      end
      message = message.." ("..concat(fields, ", ")..")"
    end
    local repID = def.repID
    types[name] = repID
    local logmsg = name.." "
    local function new(fields)
      if fields == nil then fields = {} end
      fields[1] = message
      fields._repid = repID
      return Exception(fields)
    end
    local function throw(fields)
      local except = new(fields)
      log:exception(logmsg:tag(except))
      error(except)
    end
    local function isa(value)
      return type(value) == "table" and value._repid == repID
    end
    excepts[name] = throw
    excepts["new_"..name] = new
    excepts["is_"..name] = isa
  elseif def._type == "const" then
    consts[name] = def.val
  elseif name ~= nil then
    types[name] = def.repID
  end
end

return makeaux