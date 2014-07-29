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


-- setup the ORB and connect to the bus
local orb = openbus.initORB()
local OpenBusContext = orb.OpenBusContext
OpenBusContext:setDefaultConnection(
  OpenBusContext:createConnection(bushost, busport))

-- perform operations in protected mode and handle eventual errors
local ok, result = pcall(function ()
    -- login to the bus
  OpenBusContext:getCurrentConnection():loginByPassword(entity, password
                                                                or entity)
    -- find the offered service
  local OfferRegistry = OpenBusContext:getOfferRegistry()
  return OfferRegistry:findServices{
    {name="offer.domain",value="Demo Greetings"},
    {name="greetings.language",value=language},
  }
end)
if not ok then
  utils.showerror(result, params, utils.errmsg.LoginByPassword,
                                  utils.errmsg.BusCore)
else
  for _, offer in ipairs(result) do
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
end

-- free any resoures allocated
OpenBusContext:getCurrentConnection():logout()
orb:shutdown()
