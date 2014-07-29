local _G = require "_G"
local assert = _G.assert
local error = _G.error
local ipairs = _G.ipairs

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
    excepts[name] = function(fields)
      if fields == nil then fields = {} end
      log:exception(logmsg:tag(fields))
      fields[1] = message
      fields._repid = repID
      error(Exception(fields))
    end
  elseif def._type == "const" then
    consts[name] = def.val
  elseif name ~= nil then
    types[name] = def.repID
  end
end

return makeaux