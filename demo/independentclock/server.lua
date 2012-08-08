local utils = require "utils"
local server = require "openbus.util.server"
local openbus = require "openbus"
local ComponentContext = require "scs.core.ComponentContext"


-- process command-line arguments
local bushost, busport, entity, privatekeypath, interval = ...
bushost = assert(bushost, "o 1o. argumento é o host do barramento")
busport = assert(busport, "o 2o. argumento é a porta do barramento")
busport = assert(tonumber(busport), "o 2o. argumento é um número de porta")
entity = assert(entity, "o 3o. argumento é a entidade a ser autenticada")
privatekeypath = assert(privatekeypath,
  "o 4o. argumento é o caminho da chave privada de autenticação da entidade")
local privatekey = assert(server.readfrom(privatekeypath))
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
openbus.newthread(function ()
  repeat
    print(os.date(nil, clock:getTime()))
    openbus.sleep(1)
  until false
end)


-- setup and start the ORB
local orb = openbus.initORB()
openbus.newthread(orb.run, orb)

-- load IDL definitions
local iface = orb:loadidl("interface Clock { double getTime(); };")
params.interface = iface.name

-- create service SCS component
local component = ComponentContext(orb, {
  name = iface.name,
  major_version = 1,
  minor_version = 0,
  patch_version = 0,
  platform_spec = "Lua",
})
component:addFacet(iface.name, iface.repID, clock)
local props = {{name="offer.domain",value="Demo Independent Clock"}}


-- connect to the bus
local conn
local connections = orb.OpenBusConnectionManager
repeat
  local ok, result = pcall(connections.createConnection, connections, bushost,
                                                                      busport)
  if ok then
    conn = result
  else
    utils.showerror(result, params, utils.msg.Connect)
    openbus.sleep(interval)
  end
until ok
connections:setDefaultConnection(conn)


-- create thread to register offer after (re)login
local offer
local function doregister(self)
  self.active = coroutine.running()
  local offers = conn.offers
  repeat
    local ok, result = pcall(offers.registerService, offers,
                             component.IComponent, props)
    if ok then
      offer = result
    else
      utils.showerror(result, params, utils.msg.Register)
      openbus.sleep(interval)
    end
  until ok
  self.active = nil
end
local registerer = {}
function registerer:enable()
  if offer == nil and self.active == nil then
    openbus.newthread(doregister, self)
  end
end

-- define callback for auto-relogin
function conn:onInvalidLogin()
  offer = nil
  repeat
    local ok, result = pcall(conn.loginByCertificate, conn, entity, privatekey)
    if not ok then
      if result._repid == repid.AlreadyLoggedIn then
        ok = true -- ignore this exception
      else
        utils.showerror(result, params, utils.msg.LoginByCertificate)
        openbus.sleep(interval)
      end
    end
  until ok
  registerer:enable()
end

-- login to the bus
conn:onInvalidLogin()
