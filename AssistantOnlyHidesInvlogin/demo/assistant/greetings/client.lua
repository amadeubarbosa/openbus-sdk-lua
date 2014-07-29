local utils = require "utils"
local assistant = require "openbus.assistant"


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


-- obtain an assistant
local OpenBusAssistant = assistant.create{
  bushost = bushost,
  busport = busport,
  observer = utils.failureObserver(params),
}

-- login to the bus
OpenBusAssistant:loginByPassword(entity, password or entity)

-- find offers of the required service
local offers = OpenBusAssistant:findServices{
  {name="offer.domain",value="Demo Greetings"},
  {name="greetings.language",value=language},
}

-- for each service offer found
for _, offer in ipairs(offers) do
  ok, result = pcall(function ()
    for _, name in ipairs{"GoodMorning", "GoodAfternoon", "GoodNight"} do
      -- get the facet providing the service
      local facet = assert(offer.service_ref:getFacetByName(name),
        "o serviço encontrado não provê a faceta ofertada")
      -- invoke the service
      facet:__narrow():sayGreetings()
    end
  end)
  if not ok then
    utils.showerror(result, params, utils.errmsg.Service)
  end
end

-- free any resoures allocated
OpenBusAssistant:logout()
