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
OpenBusORB:loadidlfile("callchain/messenger.idl")
local iface = OpenBusORB.types:lookup("Messenger")
params.interface = iface.name

-- create service SCS component
local component = ComponentContext(OpenBusORB, {
  name = iface.name,
  major_version = 1,
  minor_version = 0,
  patch_version = 0,
  platform_spec = "Lua",
})
component:addFacet(iface.name, iface.repID, messenger)


-- register service offer
OpenBusAssistant:registerService(component.IComponent, {
  {name="offer.role",value="actual messenger"},
  {name="offer.domain",value="Demo Chain Validation"},
})
