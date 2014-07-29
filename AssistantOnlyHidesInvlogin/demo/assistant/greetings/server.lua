local utils = require "utils"
local oo = require "openbus.util.oo"
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
  observer = utils.failureObserver(params),
}

-- login to the bus
OpenBusAssistant:loginByCertificate(entity, privatekey)

-- setup and start the ORB
local OpenBusORB = OpenBusAssistant.orb
openbus.newThread(OpenBusORB.run, OpenBusORB)

-- get bus context manager
local OpenBusContext = OpenBusORB.OpenBusContext


-- create service implementation
local Greetings = oo.class()
function Greetings:sayGreetings()
  print(self.message:format(OpenBusContext:getCallerChain().caller.entity))
end

-- load IDL definitions
local iface = OpenBusORB:loadidl("interface Greetings {void sayGreetings();};")
params.interface = iface.name

-- create service SCS components and register them
local messages = {
  English = {
    GoodMorning = "Good morning %s",
    GoodAfternoon = "Good afternoon %s",
    GoodNight = "Good night %s",
  },
  Spanish = {
    GoodMorning = "Buenos días %s",
    GoodAfternoon = "Buenas tardes %s",
    GoodNight = "Buenas noches %s",
  },
  Portuguese = {
    GoodMorning = "Bom dia %s",
    GoodAfternoon = "Boa tarde %s",
    GoodNight = "Boa noite %s",
  },
}
for language, greetings in pairs(messages) do
  -- create service SCS component
  local component = ComponentContext(OpenBusORB, {
    name = language.." "..iface.name,
    major_version = 1,
    minor_version = 0,
    patch_version = 0,
    platform_spec = "Lua",
  })
  for name, message in pairs(greetings) do
    component:addFacet(name, iface.repID, Greetings{message=message})
  end
  -- register service offer
  OpenBusAssistant:registerService(component.IComponent, {
    {name="offer.domain",value="Demo Greetings"},
    {name="greetings.language",value=language},
  })
end
