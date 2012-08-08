local utils = require "utils"
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


local repID = "IDL:Messenger:1.0"


-- variable to hold resources to be freed before termination
local conn

-- function that uses the bus to find the required service
local function findService()
  -- connect to the bus
  local connections = openbus.initORB().OpenBusConnectionManager
  conn = connections:createConnection(bushost, busport)
  connections:setDefaultConnection(conn)
  -- login to the bus
  conn:loginByPassword(entity, password or entity)
  -- find the offered service
  return conn.offers:findServices{
    {name="openbus.component.interface",value=repID},
    {name="offer.domain",value="Demo Chain Validation"},
  }
end

-- function that uses the required service through the bus
local function callService(offer)
  service = offer.service_ref
  if not service:_non_existent() then
    local facet = service:getFacet(repID)
    if facet ~= nil then
      facet:__narrow():showMessage("Hello!")
      return true
    end
  end
end

-- perform operations in protected mode and handle eventual errors
local ok, result = pcall(findService)
if not ok then
  utils.showerror(result, params, utils.msg.Connect, utils.msg.LoginByPassword)
else
  ok = nil
  for _, offer in ipairs(result) do
    ok, result = pcall(callService, offer)
    if not ok then
      if result._repid == "IDL:Unauthorized:1.0" then
        io.stderr:write("serviço com papel ",utils.getprop(offer, "offer.role"),
                        " não autorizou a chamada\n")
      elseif result._repid == "IDL:Unavailable:1.0" then
        io.stderr:write("serviço com papel ",utils.getprop(offer, "offer.role"),
                        " está indisponível\n")
      else
        utils.showerror(result, params, utils.msg.Service)
      end
    end
  end
  if ok == nil then
    io.stderr:write("não foi possível encontrar o serviço esperado\n")
  end
end

-- free any resoures allocated
if conn ~= nil then conn:logout() end
