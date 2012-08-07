local utils = require "utils"
local oo = require "openbus.util.oo"
local openbus = require "openbus"


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


-- setup and start the ORB
local orb = openbus.initORB()
openbus.newthread(orb.run, orb)
local connections = orb.OpenBusConnectionManager


-- load interface definitions
orb:loadidlfile("Multiplexing/timer.idl")
local iface = orb.types:lookup("Timer")
params.interface = iface.name


-- create service implementation
local pending = 0
local Callback = oo.class{}
function Callback:notifyTrigger()
  local conn = self.conn
  local chain = connections:getRequester():getCallerChain()
  if chain.caller.id == self.timer then
    print("notificação do timer esperado recebida!")
    --if #chain.originators ~= 1
    --or chain.originators[1].id ~= conn.login.id
    --then
    --  print("  notificação feita fora da chamada original!")
    --end
  else
    print("notificação inesperada recebida:")
    print("  recebida de: ",chain.caller.id)
    print("  esperada de: ",self.timer)
  end
  conn:logout()
  pending = pending-1
  if pending == 0 then
    connections:getDefaultConnection():logout()
    orb:shutdown()
  end
end


-- function that uses the bus to find the required service
local function newLogin()
  -- connect to the bus
  local conn = connections:createConnection(bushost, busport)
  -- login to the bus
  conn:loginByPassword(entity, password or entity)
  -- find the offered service
  return conn
end

-- function that uses the bus to find the required service
local function findService()
  -- connect to the bus
  local conn = newLogin()
  connections:setDefaultConnection(conn)
  -- find the offered service
  return conn.offers:findServices{
    {name="offer.domain",value="Demo Multiplexing"},
    {name="openbus.component.interface",value=iface.repID},
  }
end

-- function that uses the required service through the bus
local function callService(offer, timeout, callback)
  local facet = offer.service_ref:getFacet(iface.repID)
  if facet == nil then
    error("o serviço encontrado não oferece mais a faceta '"..name.."'")
  end
  facet:__narrow():newTrigger(timeout, callback)
end

-- perform operations in protected mode and handle eventual errors
local ok, result = pcall(findService)
if not ok then
  utils.showerror(result, params, utils.msg.Connect,
                                  utils.msg.LoginByPassword)
else
  for index, offer in ipairs(result) do
    openbus.newthread(function ()
      local ok, result = pcall(newLogin)
      if not ok then
        utils.showerror(result, params, utils.msg.Connect,
                                        utils.msg.LoginByPassword)
      else
        local conn = result
        connections:setRequester(conn)
        local ok, result = pcall(callService, offer, index, Callback{
          conn = conn,
          timer = utils.getprop(offer, "openbus.offer.login"),
        })
        if not ok then
          utils.showerror(result, params, utils.msg.Service)
          conn:logout()
        else
          pending = pending+1
        end
      end
    end)
  end
end

-- free any resoures allocated
