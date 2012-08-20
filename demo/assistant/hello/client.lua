local utils = require "utils"
local assistant = require "openbus.assistant"


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


-- obtain an assistant
local OpenBusAssistant = assistant.create{
  bushost = bushost,
  busport = busport,
  entity = entity,
  password = password or entity,
  observer = utils.failureObserver(params),
}

-- find offers of the required service
local offers = OpenBusAssistant:findServices{
  {name="offer.domain",value="Hello Demo"},
}

-- for each service offer found
for _, offer in ipairs(offers) do
  -- call in protected mode
  local ok, result = pcall(function ()
    -- get the facet providing the service
    local facet = assert(offer.service_ref:getFacetByName("Hello"),
      "o serviço encontrado não provê a faceta ofertada")
    -- invoke the service
    facet:__narrow():sayHello()
  end)
  if not ok then
    utils.showerror(result, params, utils.errmsg.Service)
  end
end

-- free any resoures allocated
OpenBusAssistant:shutdown()
