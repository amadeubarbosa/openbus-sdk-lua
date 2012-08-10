local utils = require "utils"
local openbus = require "openbus"
local ComponentContext = require "scs.core.ComponentContext"


-- process command-line arguments
local bushost, busport, entity, privatekeypath = ...
bushost = assert(bushost, "o 1o. argumento é o host do barramento")
busport = assert(busport, "o 2o. argumento é a porta do barramento")
busport = assert(tonumber(busport), "o 2o. argumento é um número de porta")
entity = assert(entity, "o 3o. argumento é a entidade a ser autenticada")
privatekeypath = assert(privatekeypath,
  "o 4o. argumento é o caminho da chave privada de autenticação da entidade")
local privatekey = assert(openbus.readkeyfile(privatekeypath))
local params = {
  bushost = bushost,
  busport = busport,
  entity = entity,
  privatekeypath = privatekeypath,
}


-- setup and start the ORB
local orb = openbus.initORB()
openbus.newthread(orb.run, orb)

-- get bus context manager
local OpenBusContext = orb.OpenBusContext


-- create service implementation
local function chain2str(chain)
  local entities = {}
  for _, login in ipairs(chain.originators) do
    entities[#entities+1] = login.entity
  end
  entities[#entities+1] = chain.caller.entity
  return table.concat(entities, "->")
end
local messenger = {}
function messenger:showMessage(message)
  local chain = OpenBusContext:getCallerChain()
  if chain.caller.entity ~= entity then
    print("recusando mensagem de "..chain2str(chain))
    error{_repid="IDL:Unauthorized:1.0"}
  end
  print("aceitando mensagem de "..chain2str(chain)..":", message)
end

-- load interface definitions
orb:loadidlfile("callchain/messenger.idl")
local iface = orb.types:lookup("Messenger")
params.interface = iface.name

-- create service SCS component
local component = ComponentContext(orb, {
  name = iface.name,
  major_version = 1,
  minor_version = 0,
  patch_version = 0,
  platform_spec = "Lua",
})
component:addFacet(iface.name, iface.repID, messenger)


-- connect to the bus
OpenBusContext:setDefaultConnection(
  OpenBusContext:createConnection(bushost, busport))

-- call in protected mode
local ok, result = pcall(function ()
  -- login to the bus
  OpenBusContext:getCurrentConnection():loginByCertificate(entity, privatekey)
  -- register service at the bus
  local OfferRegistry = OpenBusContext:getCoreService("OfferRegistry")
  OfferRegistry:registerService(component.IComponent, {
    {name="offer.role",value="actual messenger"},
    {name="offer.domain",value="Demo Chain Validation"},
  })
end)

-- show eventual errors
if not ok then
  utils.showerror(result, params, utils.errmsg.LoginByCertificate,
                                  utils.errmsg.Register,
                                  utils.errmsg.BusCore)
  -- free any resoures allocated
  OpenBusContext:getCurrentConnection():logout()
  orb:shutdown()
end
