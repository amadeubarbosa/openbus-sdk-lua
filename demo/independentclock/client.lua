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


-- independent clock thread
local conn
local clock
local finder = {}
openbus.newthread(function ()
  for i = 1, 10 do
    local time
    if clock ~= nil then
      local ok, result = pcall(clock.getTime, clock)
      if ok then
        time = result
      else
        clock = nil
        finder:enable() -- search for other service offers
        utils.showerror(result, params, utils.msg.Service)
      end
    end
    print(os.date(nil, time))
    openbus.sleep(1)
  end
  conn:logout()
end)


-- setup the ORB
local orb = openbus.initORB()

-- connect to the bus
local connections = orb.OpenBusConnectionManager
repeat
  local ok, result = pcall(connections.createConnection, connections, bushost,
                                                                      busport)
  if ok then
    conn = result
  else
    utils.showerror(result, params, utils.msg.Connect)
    openbus.sleep(interval)
  end
until ok
connections:setDefaultConnection(conn)

-- create thread to search for offer after (re)login or service failure
local props = {{name="offer.domain",value="Demo Independent Clock"}}
local function getfacet(offer)
  return orb:narrow(offer.service_ref:getFacetByName("Clock"))
end
local function findservices(self)
  self.active = coroutine.running()
  local offers = conn.offers
  repeat
    local ok, result = pcall(offers.findServices, offers, props)
    if ok then
      for _, offer in ipairs(result) do
        ok, result = pcall(getfacet, offer)
        if not ok then
          utils.showerror(result, params, utils.msg.Service)
        elseif result == nil then
          io.stderr:write("serviço encontrado não oferece a faceta esperada.\n")
        else
          clock = result
          self.active = nil
          return
        end
      end
      io.stderr:write("o serviço esperado não foi encontrado\n")
    else
      utils.showerror(result, params, utils.msg.Bus)
    end
    openbus.sleep(interval)
  until false
end
function finder:enable()
  if self.active == nil then
    openbus.newthread(findservices, self)
  end
end

-- define callback for auto-relogin
function conn:onInvalidLogin()
  repeat
    local ok, result = pcall(conn.loginByPassword, conn, entity, password
                                                                 or entity)
    if not ok then
      if result._repid == except.repid.AlreadyLoggedIn then
        ok = true -- ignore this exception
      else
        utils.showerror(result, params, utils.msg.LoginByPassword)
        openbus.sleep(interval)
      end
    end
  until ok
  finder:enable()
end

-- login to the bus
conn:onInvalidLogin()
