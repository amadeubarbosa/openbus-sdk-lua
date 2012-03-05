return function(chain)
  local entities = {}
  for index, login in ipairs(chain) do
    entities[index] = login.entity
  end
  return table.concat(entities, ":")
end
