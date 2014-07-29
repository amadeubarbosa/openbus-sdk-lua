local utils = require "utils"
local openbus = require "openbus"
local assistant = require "openbus.assistant"
local ComponentContext = require "scs.core.ComponentContext"


-- process command-line arguments
local bushost, busport, entity, privatekeypath = ...
bushost = assert(bushost, "o 1o. argumento é o host do barramento")
busport = assert(busport, "o 2o. argumento é a porta do barramento")
busport = assert(tonumber(busport), "o 2o. argumento é um número de porta")
entity = assert(entity, "o 3o. argumento é a entidade a ser autenticada")
privatekeypath = assert(privatekeypath,
  "o 4o. argumento é o caminho da chave privada de autenticação da entidade")
local privatekey = assert(openbus.readKeyFile(privatekeypath))
local params = {
  bushost = bushost,
  busport = busport,
  entity = entity,
  privatekeypath = privatekeypath,
}


-- create an assistant, the ORB, and the context manager
local OpenBusAssistant = assistant.create{
  bushost = bushost,
  busport = busport,
  entity = entity,
  privatekey = privatekey,
  observer = utils.failureObserver(params),
}

-- setup and start the ORB
local OpenBusORB = OpenBusAssistant.orb
openbus.newThread(OpenBusORB.run, OpenBusORB)

-- get bus context manager
local OpenBusContext = OpenBusORB.OpenBusContext


-- load interface definitions
OpenBusORB:loadidlfile("callchain/messenger.idl")
local iface = OpenBusORB.types:lookup("Messenger")
params.interface = iface.name

-- create service implementation
local function chain2str(chain)
  local entities = {}
  for _, login in ipairs(chain.originators) do
    entities[#entities+1] = login.entity
  end
  entities[#entities+1] = chain.caller.entity
  return table.concat(entities, "->")
end
local function callService(offer, message)
  local facet = assert(offer.service_ref:getFacet(iface.repID),
    "o serviço encontrado não provê a faceta ofertada")
  facet:__narrow():showMessage(message)
end
local messenger = {}
function messenger:showMessage(message)
  local chain = OpenBusContext:getCallerChain()
  print("repassando mensagem de "..chain2str(chain))
  OpenBusContext:joinChain(chain)
  for _, offer in ipairs(offers) do
    local ok, result = pcall(callService, offer, message)
    if not ok then
      utils.showerror(result, params, utils.errmsg.Service)
    else
      return
    end
  end
  io.stderr:write("serviços encontrados não estão disponíveis\n")
  error{_repid="IDL:Unavailable:1.0"}
end

-- create service SCS component
local component = ComponentContext(OpenBusORB, {
  name = iface.name,
  major_version = 1,
  minor_version = 0,
  patch_version = 0,
  platform_spec = "Lua",
})
component:addFacet(iface.name, iface.repID, messenger)


-- find offers of the required service
offers = OpenBusAssistant:findServices{
  {name="openbus.component.interface",value=iface.repID},
  {name="offer.domain",value="Demo Chain Validation"},
}

-- check if some offer was found
if #offers == 0 then
  io.stderr:write("nenhum serviço encontrado para repassar mensagens\n")
  return
end

-- register service offer
OpenBusAssistant:registerService(component.IComponent, {
  {name="offer.role",value="proxy messenger"},
  {name="offer.domain",value="Demo Chain Validation"},
})
