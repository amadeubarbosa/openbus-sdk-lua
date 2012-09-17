local utils = require "utils"
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


-- setup and start the ORB
local orb = openbus.initORB()
openbus.newThread(orb.run, orb)

-- load interface definition
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
local props = {{name="offer.domain",value="Demo Dedicated Clock"}}


-- get bus context manager
local OpenBusContext = orb.OpenBusContext

-- create thread to register offer after (re)login
local registerer = {}
function registerer:enable()
  self.disabled = nil
end
function registerer:activate()
  if not self.disabled and self.active == nil then
    openbus.newThread(function ()
      self.active = true
      repeat
        local ok, result = pcall(function ()
          local OfferRegistry = OpenBusContext:getOfferRegistry()
          OfferRegistry:registerService(component.IComponent, props)
          self.disabled = true
        end)
        if not ok then
          utils.showerror(result, params, utils.errmsg.Register,
                                          utils.errmsg.BusCore)
          openbus.sleep(interval)
        end
      until ok
      self.active = nil
    end)
  end
end

-- connect to the bus
local conn = OpenBusContext:createConnection(bushost, busport)
OpenBusContext:setDefaultConnection(conn)

-- define callback for auto-relogin
function conn:onInvalidLogin()
  registerer:enable()
  repeat
    local ok, result = pcall(self.loginByCertificate, self, entity, privatekey)
    if not ok then
      if result._repid == repid.AlreadyLoggedIn then
        ok = true -- ignore this exception
      else
        utils.showerror(result, params, utils.errmsg.LoginByCertificate,
                                        utils.errmsg.BusCore)
        openbus.sleep(interval)
      end
    end
  until ok
  registerer:activate()
end

-- login to the bus
conn:onInvalidLogin()
