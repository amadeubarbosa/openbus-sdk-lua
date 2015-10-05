return function(chain)
  local entities = {}
  for index, login in ipairs(chain.originators) do
    entities[index] = login.entity
  end
  entities[#entities+1] = chain.caller.entity
  return table.concat(entities, "->")
end
