local _G = require "_G"
local error = _G.error

local table = require "loop.table"
local memoize = table.memoize

local Exception = require "oil.corba.giop.Exception"

return memoize(function(name)
  local repId = "IDL:omg.org/CORBA/"..name..":1.0"
  return function(fields)
    if fields == nil then fields = {} end
    fields._repid = repId
    error(Exception(fields))
  end
end)
