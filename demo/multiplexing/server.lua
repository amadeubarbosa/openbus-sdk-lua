local utils = require "utils"
local oo = require "openbus.util.oo"
local server = require "openbus.util.server"
local openbus = require "openbus"
local cothread = require "cothread"
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
local connections = orb.OpenBusConnectionManager


-- create service implementation
local Timer = oo.class{}
function Timer:setConnection(conn)
  self.conn = conn
end
function Timer:getConnection()
  return self.conn
end
function Timer:newTrigger(timeout, callback)
  local conn = self.conn
  --local chain = connections:getRequester():getCallerChain()
  openbus.newthread(function ()
    openbus.sleep(timeout)
    connections:setRequester(conn)
    --conn:joinChain(chain)
    local ok, result = pcall(callback.notifyTrigger, callback)
    if not ok then
      utils.showerror(result, params, utils.msg.Service)
    end
  end)
end


-- function that registers service using a new login
local properties = {{name="offer.domain",value="Demo Multiplexing"}}
local function registerService(component)
  -- connect to the bus
  local conn = connections:createConnection(bushost, busport)
  connections:setRequester(conn)
  connections:setDispatcher(conn)
  -- login to the bus
  conn:loginByCertificate(entity, privatekey)
  -- register service at the bus
  conn.offers:registerService(component.IComponent, properties)
  -- store the connection used to register the component
  component.Timer:setConnection(conn)
end


-- load interface definitions
orb:loadidlfile("Multiplexing/timer.idl")
local iface = orb.types:lookup("Timer")
params.interface = iface.name

for i = 1, 3 do
  -- create service SCS component
  local component = ComponentContext(orb, {
    name = iface.name,
    major_version = 1,
    minor_version = 0,
    patch_version = 0,
    platform_spec = "Lua",
  })
  component:addFacet(iface.name, iface.repID, Timer())
  -- try to register service
  local ok, result = pcall(registerService, component)
  if not ok then
    utils.showerror(result, params,
      utils.msg.Connect,
      utils.msg.LoginByCertificate,
      utils.msg.Register)
    -- free any resoures allocated
    local conn = component.Timer:getConnection()
    if conn ~= nil then
      conn:logout()
    end
  end
end
