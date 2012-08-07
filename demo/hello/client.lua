local utils = require "utils"
local openbus = require "openbus"


-- process command-line arguments
local bushost, busport, entity, password = ...
bushost = assert(bushost, "o 1o. argumento é o host do barramento")
busport = assert(busport, "o 2o. argumento é a porta do barramento")
busport = assert(tonumber(busport), "o 2o. argumento é um número de porta")
entity = assert(entity, "o 3o. argumento é a entidade a ser autenticada")
local params = {
  bushost = bushost,
  busport = busport,
  entity = entity,
}


-- variable to hold resources to be freed before termination
local conn

-- function that uses the bus to find the required service
local function findService()
  -- connect to the bus
  local connections = openbus.initORB().OpenBusConnectionManager
  conn = connections:createConnection(bushost, busport)
  connections:setDefaultConnection(conn)
  -- login to the bus
  conn:loginByPassword(entity, password or entity)
  -- find the offered service
  return conn.offers:findServices{{name="offer.domain",value="Demo Hello"}}
end

-- function that uses the required service through the bus
local function callService(offers)
  for _, offer in ipairs(offers) do
    service = offer.service_ref
    if not service:_non_existent() then
      local facet = service:getFacetByName("Hello")
      if facet == nil then
        error("o serviço encontrado não oferece mais a faceta 'Hello'")
      end
      return facet:__narrow():sayHello()
    end
  end
  error("não foi possível encontrar o serviço esperado")
end

-- perform operations in protected mode and handle eventual errors
local ok, result = pcall(findService)
if not ok then
  utils.showerror(result, params, utils.msg.Connect, utils.msg.LoginByPassword)
else
  ok, result = pcall(callService, result)
  if not ok then
    utils.showerror(result, params, utils.msg.Service)
  end
end

-- free any resoures allocated
if conn ~= nil then conn:logout() end
