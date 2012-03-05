local table = require "loop.table"
local memoize = table.memoize

local CyclicSets = require "loop.collection.CyclicSets"

local module = {}

function module.LRU(retrieve, maxsize)
  if maxsize == nil then maxsize = 128 end
  local usage = CyclicSets()
  local size = 0
  local lastused
  local map
  map = memoize(function(key)
    usage:add(key, lastused)
    lastused = key
    if size < maxsize then
      size = size+1
      return retrieve(key)
    else
      local replacedkey = usage:removefrom(lastused)
      local replaced = map[replacedkey]
      map[replacedkey] = nil
      return retrieve(key, replacedkey, replaced)
    end
  end)
  return map
end

return module
