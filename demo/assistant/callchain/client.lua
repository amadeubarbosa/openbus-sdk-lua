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

local repID = "IDL:Messenger:1.0"

-- find offers of the required service
local offers = OpenBusAssistant:findServices{
  {name="openbus.component.interface",value=repID},
  {name="offer.domain",value="Demo Chain Validation"},
}

ok = nil
for _, offer in ipairs(offers) do
  ok, result = pcall(function ()
    -- get the facet providing the service
    local facet = assert(offer.service_ref:getFacet(repID),
      "o serviço encontrado não provê a faceta ofertada")
    -- invoke the service
    facet:__narrow():showMessage("Hello!")
  end)
  if not ok then
    if result._repid == "IDL:Unauthorized:1.0" then
      io.stderr:write("serviço com papel ",utils.getprop(offer, "offer.role"),
                      " não autorizou a chamada\n")
    elseif result._repid == "IDL:Unavailable:1.0" then
      io.stderr:write("serviço com papel ",utils.getprop(offer, "offer.role"),
                      " está indisponível\n")
    else
      utils.showerror(result, params, utils.errmsg.Service)
    end
  end
end
if ok == nil then
  io.stderr:write("não foi possível encontrar o serviço esperado\n")
end

-- free any resoures allocated
OpenBusAssistant:shutdown()
