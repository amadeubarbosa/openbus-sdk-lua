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


-- setup and start the ORB
local orb = openbus.initORB()
openbus.newthread(orb.run, orb)

-- load interface definitions
orb:loadidlfile("callchain/messenger.idl")
local iface = orb.types:lookup("Messenger")
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
local conn
local messenger = {}
function messenger:showMessage(message)
  local chain = conn:getCallerChain()
  if chain.caller.entity ~= entity then
    print("recusando mensagem de "..chain2str(chain))
    error{_repid="IDL:Unauthorized:1.0"}
  end
  print("aceitando mensagem de "..chain2str(chain)..":", message)
end
  
-- create service SCS component
local component = ComponentContext(orb, {
  name = iface.name,
  major_version = 1,
  minor_version = 0,
  patch_version = 0,
  platform_spec = "Lua",
})
component:addFacet(iface.name, iface.repID, messenger)

-- call in protected mode
local ok, result = pcall(function ()
  -- connect to the bus
  local connections = orb.OpenBusConnectionManager
  conn = connections:createConnection(bushost, busport)
  connections:setDefaultConnection(conn)
  
  -- login to the bus
  conn:loginByCertificate(entity, privatekey)
  
  -- register service at the bus
  conn.offers:registerService(component.IComponent, {
    {name="offer.role",value="actual messenger"},
    {name="offer.domain",value="Demo Chain Validation"},
  })
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
