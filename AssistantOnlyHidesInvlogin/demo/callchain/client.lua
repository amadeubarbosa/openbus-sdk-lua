local utils = require "utils"
local openbus = require "openbus"


-- process command-line arguments
local bushost, busport, entity, password = ...
bushost = assert(bushost, "o 1o. argumento � o host do barramento")
busport = assert(busport, "o 2o. argumento � a porta do barramento")
busport = assert(tonumber(busport), "o 2o. argumento � um n�mero de porta")
entity = assert(entity, "o 3o. argumento � a entidade a ser autenticada")
local params = {
  bushost = bushost,
  busport = busport,
  entity = entity,
}


-- setup the ORB and connect to the bus
local OpenBusContext = openbus.initORB().OpenBusContext
OpenBusContext:setDefaultConnection(
  OpenBusContext:createConnection(bushost, busport))

local repID = "IDL:Messenger:1.0"

-- call in protected mode
local ok, result = pcall(function ()
  -- login to the bus
  OpenBusContext:getCurrentConnection():loginByPassword(entity, password
                                                                or entity)
  -- find the offered service
  local OfferRegistry = OpenBusContext:getOfferRegistry()
  return OfferRegistry:findServices{
    {name="openbus.component.interface",value=repID},
    {name="offer.domain",value="Demo Call Chain"},
  }
end)
if not ok then
  utils.showerror(result, params, utils.errmsg.LoginByPassword,
                                  utils.errmsg.BusCore)
else
  ok = nil
  for _, offer in ipairs(result) do
    ok, result = pcall(function ()
      -- get the facet providing the service
      local facet = assert(offer.service_ref:getFacet(repID),
        "o servi�o encontrado n�o prov� a faceta ofertada")
      -- invoke the service
      facet:__narrow():showMessage("Hello!")
    end)
    if not ok then
      if result._repid == "IDL:Unauthorized:1.0" then
        io.stderr:write("servi�o com papel ",utils.getprop(offer, "offer.role"),
                        " n�o autorizou a chamada\n")
      elseif result._repid == "IDL:Unavailable:1.0" then
        io.stderr:write("servi�o com papel ",utils.getprop(offer, "offer.role"),
                        " est� indispon�vel\n")
      else
        utils.showerror(result, params, utils.errmsg.Service)
      end
    end
  end
  if ok == nil then
    io.stderr:write("n�o foi poss�vel encontrar o servi�o esperado\n")
  end
end

-- free any resoures allocated
OpenBusContext:getCurrentConnection():logout()
