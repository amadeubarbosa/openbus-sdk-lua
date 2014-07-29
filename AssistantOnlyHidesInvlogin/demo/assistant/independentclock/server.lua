local utils = require "utils"
local openbus = require "openbus"
local assistant = require "openbus.assistant"
local ComponentContext = require "scs.core.ComponentContext"


-- process command-line arguments
local bushost, busport, entity, privatekeypath, interval = ...
bushost = assert(bushost, "o 1o. argumento é o host do barramento")
busport = assert(busport, "o 2o. argumento é a porta do barramento")
busport = assert(tonumber(busport), "o 2o. argumento é um número de porta")
entity = assert(entity, "o 3o. argumento é a entidade a ser autenticada")
privatekeypath = assert(privatekeypath,
  "o 4o. argumento é o caminho da chave privada de autenticação da entidade")
local privatekey = assert(openbus.readKeyFile(privatekeypath))
interval = assert(tonumber(interval or 1), "o 5o. argumento é um tempo entre "..
                  "tentativas de acesso ao barramento em virtude de falhas")
local params = {
  bushost = bushost,
  busport = busport,
  entity = entity,
  privatekeypath = privatekeypath,
}


-- create service implementation
local clock = {}
function clock:getTime()
  return os.time() - 24*60*60 -- send the time of the same moment yesterday
end

-- independent clock thread
openbus.newThread(function ()
  repeat
    print(os.date(nil, clock:getTime()))
    openbus.sleep(1)
  until false
end)


-- create an assistant, the ORB, and the context manager
local OpenBusAssistant = assistant.create{
  bushost = bushost,
  busport = busport,
  observer = utils.failureObserver(params),
}

-- login to the bus
OpenBusAssistant:loginByCertificate(entity, privatekey)

-- setup and start the ORB
local OpenBusORB = OpenBusAssistant.orb
openbus.newThread(OpenBusORB.run, OpenBusORB)


-- load interface definition
local iface = OpenBusORB:loadidl("interface Clock { double getTime(); };")
params.interface = iface.name

-- create service SCS component
local component = ComponentContext(OpenBusORB, {
  name = iface.name,
  major_version = 1,
  minor_version = 0,
  patch_version = 0,
  platform_spec = "Lua",
})
component:addFacet(iface.name, iface.repID, clock)


-- register service offer
OpenBusAssistant:registerService(component.IComponent, {
  {name="offer.domain",value="Demo Independent Clock"},
})
