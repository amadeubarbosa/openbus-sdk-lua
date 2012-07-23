return function(chain)
  local entities = {chain.caller.entity}
  for index, login in ipairs(chain.originators) do
    entities[1+index] = login.entity
  end
  return table.concat(entities, ":")
end
