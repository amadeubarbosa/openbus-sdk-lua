local table = require "loop.table"
local log = require "openbus.util.logger"
local openbus = require "openbus"
local ComponentContext = require "scs.core.ComponentContext"

require "openbus.test.util"

-- setup and start the ORB
local orb = openbus.initORB()
openbus.newThread(orb.run, orb)

-- load interface definition
orb:loadidlfile("idl/hello.idl")
local iface = orb.types:lookup("tecgraf::openbus::interop::simple::Hello")

-- customize test configuration for this case
settestcfg(iface, ...)

-- read login private key
local key = assert(openbus.readKeyFile(syskey))

-- get bus context manager
local OpenBusContext = orb.OpenBusContext

-- create service implementation
local hello = {}
function hello:sayHello()
  local conn = OpenBusContext:getCurrentConnection()
  log:TEST("relogging entity ",system)
  conn:logout()
  conn:loginByCertificate(system, key)
  local chain = OpenBusContext:getCallerChain()
  local entity = chain.caller.entity
  log:TEST("got call from ",entity)
  OpenBusContext:joinChain(chain)
  
  -- define service properties
  local searchprops = table.copy(properties)
  searchprops[#searchprops+1] =
    {name="reloggedjoin.role",value="server"}

  -- find the offered service
  log:TEST("retrieve hello service")
  local OfferRegistry = OpenBusContext:getOfferRegistry()
  for _, offer in ipairs(findoffers(OfferRegistry, searchprops)) do
    local entity = getprop(offer.properties, "openbus.offer.entity")
    log:TEST("found service of ",entity,"!")
    local hello = offer.service_ref:getFacetByName(iface.name):__narrow(iface)
    return hello:sayHello()
  end
  return "no service found!"
end

-- create service SCS component
local component = ComponentContext(orb, {
  name = "Hello",
  major_version = 1,
  minor_version = 0,
  patch_version = 0,
  platform_spec = "Lua",
})
component:addFacet(iface.name, iface.repID, hello)

-- connect to the bus
local conn = OpenBusContext:createConnection(bushost, busport)
OpenBusContext:setDefaultConnection(conn)

-- login to the bus
conn:loginByCertificate(system, key)

-- define service properties
local servprops = table.copy(properties)
servprops[#servprops+1] =
  {name="reloggedjoin.role",value="proxy"}

-- offer service
local OfferRegistry = OpenBusContext:getOfferRegistry()
OfferRegistry:registerService(component.IComponent, servprops)

log:TEST("hello service proxy ready!")
