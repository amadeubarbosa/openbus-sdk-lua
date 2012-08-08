local utils = require "utils"
local openbus = require "openbus"


-- process command-line arguments
local bushost, busport, entity, password, language = ...
bushost = assert(bushost, "o 1o. argumento é o host do barramento")
busport = assert(busport, "o 2o. argumento é a porta do barramento")
busport = assert(tonumber(busport), "o 2o. argumento é um número de porta")
entity = assert(entity, "o 3o. argumento é a entidade a ser autenticada")
language = assert(language or "Portuguese",
  "o 4o. argumento deve ser uma das opções: English, Spanish, Portuguese")
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
  return conn.offers:findServices{
    {name="offer.domain",value="Demo Greetings"},
    {name="greetings.language",value=language},
  }
end

-- function that uses the required service through the bus
local facets = {"GoodMorning", "GoodAfternoon", "GoodNight"}
local function callService(offers)
  for _, offer in ipairs(offers) do
    service = offer.service_ref
    if not service:_non_existent() then
      for _, name in ipairs(facets) do
        local facet = service:getFacetByName(name)
        if facet == nil then
          error("o serviço encontrado não oferece mais a faceta '"..name.."'")
        end
        facet:__narrow():sayGreetings()
      end
      return
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
