local utils = require "utils"
local openbus = require "openbus"
local assistant = require "openbus.assistant"


-- process command-line arguments
local bushost, busport, entity, password, interval = ...
bushost = assert(bushost, "o 1o. argumento é o host do barramento")
busport = assert(busport, "o 2o. argumento é a porta do barramento")
busport = assert(tonumber(busport), "o 2o. argumento é um número de porta")
entity = assert(entity, "o 3o. argumento é a entidade a ser autenticada")
interval = assert(tonumber(interval or 1), "o 5o. argumento é um tempo entre "..
                  "tentativas de acesso ao barramento em virtude de falhas")
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


-- create object to search for offer
local clock
local searching
local function findclock()
  if not searching then
    openbus.newThread(function ()
      searching = true
      clock = nil -- discard current service reference
      repeat
        -- find offers of the required service
        local props = {{name="offer.domain",value="Demo Independent Clock"}}
        local offers = OpenBusAssistant:findServices(props, 0)
        for _, offer in ipairs(offers) do
          local ok, result = pcall(function ()
            local facet = assert(offer.service_ref:getFacetByName("Clock"),
              "o serviço encontrado não provê a faceta ofertada")
            clock = facet:__narrow()
          end)
          if not ok then
            utils.showerror(result, params, utils.errmsg.Service)
          else
            break
          end
        end
        openbus.sleep(interval)
      until clock
      searching = nil
    end)
  end
end

findclock()


-- independent clock
for i = 1, 10 do
  local time
  if clock ~= nil then
    local ok, result = pcall(clock.getTime, clock)
    if ok then
      time = result
    else
      utils.showerror(result, params, utils.errmsg.Service)
      findclock()
    end
  end
  print(os.date(nil, time))
  openbus.sleep(1)
end


-- free any resoures allocated
OpenBusAssistant:logout()

clock = true
