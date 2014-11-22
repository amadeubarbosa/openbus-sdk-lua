local _G = require "_G"
local next = _G.next
local rawget = _G.rawget
local select = _G.select

local table = require "loop.table"
local memoize = table.memoize

local function create()
  return memoize(create)
end

local function remove(table, key, ...)
  if select("#", ...) == 0 then
    local value = table[key]
    table[key] = nil
    return value
  else
    local value = rawget(table, key)
    if value ~= nil then
      local result = remove(value, ...)
      if result ~= nil and next(value) == nil then
        table[key] = nil
      end
      return result
    end
  end
end

local function get(table, key, ...)
  if select("#", ...) == 0 then
    return rawget(table, key)
  else
    local value = rawget(table, key)
    if value ~= nil then
      return get(value, ...)
    end
  end
end

return {
  create = create,
  remove = remove,
  get = get,
}
