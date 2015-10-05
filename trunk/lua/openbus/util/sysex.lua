local _G = require "_G"
local error = _G.error

local string = require "string"
local find = string.find
local substring = string.sub

local table = require "loop.table"
local memoize = table.memoize

local giop = require "oil.corba.giop"
local repids = giop.SystemExceptionIDs

local Exception = require "oil.corba.giop.Exception"

return memoize(function(name)
  local checker = find(name, "^is_")
  local repid = repids[checker and substring(name, 4) or name]
  if checker then
    return function(except, minor, completed)
      return except._repid == repid
         and (minor == nil or except.minor == minor)
         and (completed == nil or except.completed == completed)
    end
  else
    return function(fields)
      if fields == nil then fields = {} end
      fields._repid = repid
      error(Exception(fields))
    end
  end
end)
