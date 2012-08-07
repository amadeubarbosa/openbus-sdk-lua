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


-- independent clock thread
function retry()
  if retries > 0 then
    retries = retries-1
    openbus.sleep(interval)
    return true
  end
end

-- setup the ORB
local orb = openbus.initORB()

-- connect to the bus
local conn
local connections = orb.OpenBusConnectionManager
repeat
  local ok, result = pcall(connections.createConnection, connections, bushost,
                                                                      busport)
  if ok then
    conn = result
  else
    utils.showerror(result, params, utils.msg.Connect)
    if not retry() then
      return
    end
  end
until ok
connections:setDefaultConnection(conn)

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
      end
    end
  until ok or not retry()
end

-- login to the bus
conn:onInvalidLogin()

-- search for offer
local props = {{name="offer.domain",value="Demo Independent Clock"}}
local function getfacet(offer)
  return orb:narrow(offer.service_ref:getFacetByName("Clock"))
end
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
        ok, result = pcall(result.getTime, result)
        if not ok then
          utils.showerror(result, params, utils.msg.Service)
        end
        conn:logout()
        return print(os.date(nil, result))
      end
    end
    io.stderr:write("o serviço esperado não foi encontrado\n")
  else
    utils.showerror(result, params, utils.msg.Bus)
  end
  if not retry() then
    conn:logout()
    return
  end
until false
