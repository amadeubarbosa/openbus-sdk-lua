local utils = require "utils"
local except = require "openbus.util.except"
local openbus = require "openbus"


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


-- setup the ORB
local orb = openbus.initORB()

-- get bus context manager
local OpenBusContext = orb.OpenBusContext


-- independent clock thread
local finder = {}
openbus.newThread(function ()
  for i = 1, 10 do
    local time
    local clock = finder.found
    if clock ~= nil then
      local ok, result = pcall(clock.getTime, clock)
      if ok then
        time = result
      else
        utils.showerror(result, params, utils.errmsg.Service)
        finder.found = nil -- discard current service reference
        finder:activate() -- search for other service offers
      end
    end
    print(os.date(nil, time))
    openbus.sleep(1)
  end
  OpenBusContext:getCurrentConnection():logout()
end)


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
        openbus.sleep(interval)
      end
    end
  until ok
  finder:activate()
end

-- create object to search for offer after (re)login
function finder:activate()
  if self.found == nil and self.active == nil then
    openbus.newThread(function ()
      self.active = true
      repeat
        local OfferRegistry = OpenBusContext:getOfferRegistry()
        local ok, result = pcall(OfferRegistry.findServices, OfferRegistry,
          {{name="offer.domain",value="Demo Independent Clock"}})
        if not ok then
          utils.showerror(result, params, utils.errmsg.BusCore)
        else
          for _, offer in ipairs(result) do
            local ok, result = pcall(function ()
              local facet = assert(offer.service_ref:getFacetByName("Clock"),
                "o serviço encontrado não provê a faceta ofertada")
              self.found = facet:__narrow()
            end)
            if not ok then
              utils.showerror(result, params, utils.errmsg.Service)
            else
              break
            end
          end
          if self.found == nil then
            io.stderr:write("o serviço esperado não foi encontrado\n")
          else
            break
          end
        end
        openbus.sleep(interval)
      until false
      self.active = nil
    end)
  end
end

-- login to the bus
conn:onInvalidLogin()
orb:shutdown()
