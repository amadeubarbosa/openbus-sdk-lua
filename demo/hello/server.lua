local utils = require "utils"
local server = require "openbus.util.server"
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
local privatekey = assert(server.readfrom(privatekeypath))
local params = {
  bushost = bushost,
  busport = busport,
  entity = entity,
  privatekeypath = privatekeypath,
}


-- create service implementation
local conn
local hello = {}
function hello:sayHello()
  print("Hello "..conn:getCallerChain().caller.entity.."!")
end
  
-- setup and start the ORB
local orb = openbus.initORB()
openbus.newthread(orb.run, orb)

-- load IDL definitions
local iface = orb:loadidl("interface Hello { void sayHello(); };")
params.interface = iface.name

-- create service SCS component
local component = ComponentContext(orb, {
  name = iface.name,
  major_version = 1,
  minor_version = 0,
  patch_version = 0,
  platform_spec = "Lua",
})
component:addFacet("Hello", iface.repID, hello)
local props = {{name="offer.domain",value="Demo Hello"}}

-- call in protected mode
local ok, result = pcall(function ()
  -- connect to the bus
  local connections = orb.OpenBusConnectionManager
  conn = connections:createConnection(bushost, busport)
  connections:setDefaultConnection(conn)
  -- login to the bus
  conn:loginByCertificate(entity, privatekey)
  -- register service at the bus
  conn.offers:registerService(component.IComponent, props)
end)

-- show eventual errors
if not ok then
  utils.showerror(result, params,
    utils.msg.Connect,
    utils.msg.LoginByCertificate,
    utils.msg.Register)
  -- free any resoures allocated
  if conn ~= nil then
    conn:logout()
  end
  orb:shutdown()
end
