local utils = require "utils"
local assistant = require "openbus.assistant"


-- process command-line arguments
local bushost, busport, entity, password, interval, timeout = ...
bushost = assert(bushost, "o 1o. argumento é o host do barramento")
busport = assert(busport, "o 2o. argumento é a porta do barramento")
busport = assert(tonumber(busport), "o 2o. argumento é um número de porta")
entity = assert(entity, "o 3o. argumento é a entidade a ser autenticada")
interval = assert(tonumber(interval or 1), "o 5o. argumento é um tempo entre "..
                  "tentativas de acesso ao barramento em virtude de falhas")
retries = assert(tonumber(timeout or 10), "o 6o. argumento é o número máximo "..
                  "de tentativas de acesso ao barramento em virtude de falhas")
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
local props = {{name="offer.domain",value="Demo Dedicated Clock"}}
local offers = OpenBusAssistant:findServices(props, retries)

-- for each service offer found
local timestamp
for _, offer in ipairs(offers) do
  local ok, result = pcall(function ()
    -- get the facet providing the service
    local facet = assert(offer.service_ref:getFacetByName("Clock"),
      "o serviço encontrado não provê a faceta ofertada")
    -- invoke the service
    timestamp = facet:__narrow():getTime()
  end)
  if not ok then
    utils.showerror(result, params, utils.errmsg.Service)
  else
    break
  end
end
if timestamp == nil then
  io.stderr:write("não foi possível utilizar os serviços encontrados\n")
end

-- show the obtained timestamp, if any
print(os.date(nil, timestamp))


-- free any resoures allocated
OpenBusAssistant:shutdown()
OpenBusAssistant.orb:shutdown()
