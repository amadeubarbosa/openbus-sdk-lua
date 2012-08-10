local utils = require "utils"
local except = require "openbus.util.except"
local openbus = require "openbus"


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


-- function to count the number os remaining retries
local function retry()
  if retries > 0 then
    retries = retries-1
    openbus.sleep(interval)
    return true
  end
end

-- setup the ORB
local orb = openbus.initORB()

-- get bus context manager
local OpenBusContext = orb.OpenBusContext

-- connect to the bus
local conn = OpenBusContext:createConnection(bushost, busport)
OpenBusContext:setDefaultConnection(conn)

-- define callback for auto-relogin
function conn:onInvalidLogin()
  repeat
    local ok, result = pcall(self.loginByPassword, self, entity, password
                                                                 or entity)
    if not ok then
      if result._repid == except.repid.AlreadyLoggedIn then
        ok = true -- ignore this exception
      else
        utils.showerror(result, params, utils.errmsg.LoginByPassword,
                                        utils.errmsg.BusCore)
      end
    end
  until ok or not retry()
end

-- login to the bus
conn:onInvalidLogin()

-- search for offer
local timestamp
local props = {{name="offer.domain",value="Demo Independent Clock"}}
repeat
  local OfferRegistry = OpenBusContext:getCoreService("OfferRegistry")
  local ok, result = pcall(OfferRegistry.findServices, OfferRegistry, props)
  if not ok then
    utils.showerror(result, params, utils.errmsg.BusCore)
  else
    for _, offer in ipairs(result) do
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
  end
until timestamp or not retry()

-- free any resoures allocated
conn:logout()


print(os.date(nil, timestamp))

