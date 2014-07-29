local utils = require "utils"
local oo = require "openbus.util.oo"
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
local privatekey = assert(openbus.readKeyFile(privatekeypath))
local params = {
  bushost = bushost,
  busport = busport,
  entity = entity,
  privatekeypath = privatekeypath,
}


-- setup and start the ORB
local orb = openbus.initORB()
openbus.newThread(orb.run, orb)

-- get bus context manager
local OpenBusContext = orb.OpenBusContext


-- create service implementation
local Greetings = oo.class()
function Greetings:sayGreetings()
  print(self.message:format(OpenBusContext:getCallerChain().caller.entity))
end

-- load IDL definitions
local iface = orb:loadidl("interface Greetings { void sayGreetings(); };")
params.interface = iface.name

-- create service SCS components
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
local components = {}
for language, greetings in pairs(messages) do
  local component = ComponentContext(orb, {
    name = language.." "..iface.name,
    major_version = 1,
    minor_version = 0,
    patch_version = 0,
    platform_spec = "Lua",
  })
  for name, message in pairs(greetings) do
    component:addFacet(name, iface.repID, Greetings{message=message})
  end
  components[#components+1] = {
    component = component,
    properties = {
      {name="offer.domain",value="Demo Greetings"},
      {name="greetings.language",value=language},
    },
  }
end


-- connect to the bus
OpenBusContext:setDefaultConnection(
  OpenBusContext:createConnection(bushost, busport))

-- call in protected mode
local ok, result = pcall(function ()
  -- login to the bus
  OpenBusContext:getCurrentConnection():loginByCertificate(entity, privatekey)
  -- register service at the bus
  local OfferRegistry = OpenBusContext:getOfferRegistry()
  for _, info in ipairs(components) do
    OfferRegistry:registerService(info.component.IComponent, info.properties)
  end
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
