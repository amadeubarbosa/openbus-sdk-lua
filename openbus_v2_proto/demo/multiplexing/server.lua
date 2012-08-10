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
local Timer = oo.class()
function Timer:newTrigger(timeout, callback)
  local chain = OpenBusContext:getCallerChain()
  local conn = OpenBusContext:getCurrentConnection()
  openbus.newthread(function ()
    openbus.sleep(timeout)
    OpenBusContext:setCurrentConnection(conn)
    OpenBusContext:joinChain(chain)
    local ok, result = pcall(callback.notifyTrigger, callback)
    if not ok then
      utils.showerror(result, params, utils.errmsg.Service)
    end
  end)
end


local TimerConn = {}
function OpenBusContext:onCallDispatch(busid, callerid, objkey, operation, ...)
  local servant = orb.ServantManager.servants:retrieve(objkey)
  return TimerConn[servant and servant.__servant]
      or select(2, next(TimerConn)) -- use any connection, if exists
end


-- load interface definitions
orb:loadidlfile("Multiplexing/timer.idl")
local iface = orb.types:lookup("Timer")
params.interface = iface.name

for i = 1, 3 do
  -- instantiate implementaiton
  local timer = Timer()
  -- create service SCS component
  local component = ComponentContext(orb, {
    name = iface.name,
    major_version = 1,
    minor_version = 0,
    patch_version = 0,
    platform_spec = "Lua",
  })
  component:addFacet(iface.name, iface.repID, timer)
  -- connect to the bus
  local conn = OpenBusContext:createConnection(bushost, busport)
  OpenBusContext:setCurrentConnection(conn)
  -- associate connection to the servant
  TimerConn[timer] = conn
  -- try to register service
  local ok, result = pcall(function ()
    -- login to the bus
    conn:loginByCertificate(entity, privatekey)
    -- register service at the bus
    local OfferRegistry = OpenBusContext:getCoreService("OfferRegistry")
    OfferRegistry:registerService(component.IComponent,
      {{name="offer.domain",value="Demo Multiplexing"}})
  end)
  if not ok then
    utils.showerror(result, params, utils.errmsg.LoginByCertificate,
                                    utils.errmsg.Register,
                                    utils.errmsg.BusCore)
    -- free any resoures allocated
    OpenBusContext:getCurrentConnection():logout()
    orb:shutdown()
  end
end
