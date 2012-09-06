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
openbus.newThread(orb.run, orb)

-- get bus context manager
local OpenBusContext = orb.OpenBusContext


-- load interface definitions
orb:loadidlfile("Multiplexing/timer.idl")
local iface = orb.types:lookup("Timer")
params.interface = iface.name


-- create callback implementation
local pending = 0
local Callback = oo.class{}
function Callback:notifyTrigger()
  local chain = OpenBusContext:getCallerChain()
  local timerId = utils.getprop(self.timerOffer, "openbus.offer.login")
  if chain.caller.id == timerId then
    print("notificação do timer esperado recebida!")
    if #chain.originators ~= 1
    or chain.originators[1].id ~= self.loginId
    then
      print("  notificação feita fora da chamada original!")
    end
  else
    print("notificação inesperada recebida:")
    print("  recebida de: ",chain.caller.id)
    print("  esperada de: ",timerId)
  end
  pending = pending-1
  if pending == 0 then
    -- free any resoures allocated
    OpenBusContext:getDefaultConnection():logout()
    orb:shutdown()
  end
end


-- function that creates connections logged to the bus
local connprops = { accesskey = assert(openbus.newKey()) }
local function newLogin()
  -- connect to the bus
  local conn = OpenBusContext:createConnection(bushost, busport, connprops)
  -- login to the bus
  conn:loginByPassword(entity, password or entity)
  -- return the connection with the new login
  return conn
end

-- perform operations in protected mode and handle eventual errors
local ok, result = pcall(function ()
  -- connect to the bus
  OpenBusContext:setDefaultConnection(newLogin())
  -- find the offered service
  local OfferRegistry = OpenBusContext:getOfferRegistry()
  return OfferRegistry:findServices{
    {name="offer.domain",value="Demo Multiplexing"},
    {name="openbus.component.interface",value=iface.repID},
  }
end)
if not ok then
  utils.showerror(result, params, utils.errmsg.LoginByPassword,
                                  utils.errmsg.BusCore)
else
  -- for each service offer found
  for index, offer in ipairs(result) do
    -- use offer in a separated thread
    openbus.newThread(function ()
      -- get new login in protected mode
      local ok, result = pcall(newLogin)
      if not ok then
        utils.showerror(result, params, utils.errmsg.LoginByPassword,
                                        utils.errmsg.BusCore)
      else
        -- call the service found using the new login
        local conn = result
        OpenBusContext:setCurrentConnection(conn)
        local ok, result = pcall(function ()
          local facet = assert(offer.service_ref:getFacet(iface.repID),
            "o serviço encontrado não provê a faceta ofertada")
          assert(facet:__narrow()):newTrigger(index, Callback{
            loginId = conn.login.id,
            timerOffer = offer,
          })
        end)
        if not ok then
          utils.showerror(result, params, utils.errmsg.Service)
        else
          pending = pending+1
        end
        conn:logout()
      end
    end)
  end
end
