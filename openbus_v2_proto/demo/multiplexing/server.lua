local coroutine = require "coroutine"
local cothread = require "cothread"
local openbus = require "openbus.multiplexed"
local ComponentContext = require "scs.core.ComponentContext"

-- setup and start the ORB
local orb1 = openbus.initORB()
orb1:loadidl "interface Hello { void sayHello(); };"
cothread.next(coroutine.create(orb1.run), orb1)
local orb2 = openbus.initORB()
orb2:loadidl "interface Hello { void sayHello(); };"
cothread.next(coroutine.create(orb2.run), orb2)

-- connect to the bus
local conn1AtBus1WithOrb1 = openbus.connect("localhost", 2089, orb1)
local conn2AtBus1WithOrb1 = openbus.connect("localhost", 2089, orb1)
local connAtBus2WithOrb1 = openbus.connect("localhost", 2090, orb1)
local connAtBus1WithOrb2 = openbus.connect("localhost", 2089, orb2)

-- setup action on login termination
function conn1AtBus1WithOrb1:onInvalidLogin()
  print("login conn1AtBus1WithOrb1 terminated")
  conn1AtBus1WithOrb1:close() -- free connection resources
  conn1AtBus1WithOrb1 = nil
  if conn2AtBus1WithOrb1 == nil and connAtBus2WithOrb1 == nil then
    print("shutting ORB1 down")
    orb1:shutdown() -- stop the ORB and free all its resources
  end
end
function conn2AtBus1WithOrb1:onInvalidLogin()
  print("login conn2AtBus1WithOrb1 terminated")
  conn2AtBus1WithOrb1:close() -- free connection resources
  conn2AtBus1WithOrb1 = nil
  if conn1AtBus1WithOrb1 == nil and connAtBus2WithOrb1 == nil then
    print("shutting ORB1 down")
    orb1:shutdown() -- stop the ORB and free all its resources
  end
end
function connAtBus2WithOrb1:onInvalidLogin()
  print("login connAtBus2WithOrb1 terminated")
  connAtBus2WithOrb1:close() -- free connection resources
  connAtBus2WithOrb1 = nil
  if conn1AtBus1WithOrb1 == nil and conn2AtBus1WithOrb1 == nil then
    print("shutting ORB1 down")
    orb1:shutdown() -- stop the ORB and free all its resources
  end
end
function connAtBus1WithOrb2:onInvalidLogin()
  print("login connAtBus1WithOrb2 terminated, shutting ORB2 down")
  connAtBus1WithOrb2:close() -- free connection resources
  connAtBus1WithOrb2 = nil
  orb2:shutdown() -- stop the ORB and free all its resources
end

-- create service implementation
local hello = {}
function hello:sayHello()
  local chain = conn1AtBus1WithOrb1:getCallerChain()
             or connAtBus2WithOrb1:getCallerChain()
             or connAtBus1WithOrb2:getCallerChain()
  print("Hello from "..chain.callers[1].entity.."@"..chain.busid.."!")
end

-- create service SCS component
local component1 = ComponentContext(orb1, {
  name = "Hello",
  major_version = 1,
  minor_version = 0,
  patch_version = 0,
  platform_spec = "",
})
component1:addFacet("hello", orb1.types:lookup("Hello").repID, hello)
local component2 = ComponentContext(orb2, {
  name = "Hello",
  major_version = 1,
  minor_version = 0,
  patch_version = 0,
  platform_spec = "",
})
component2:addFacet("hello", orb2.types:lookup("Hello").repID, hello)

-- set incoming connections
local multiplexer = orb1.OpenBusConnectionMultiplexer
multiplexer:setIncomingConnection(conn1AtBus1WithOrb1.busid, conn1AtBus1WithOrb1)
multiplexer:setIncomingConnection(connAtBus2WithOrb1.busid, connAtBus2WithOrb1)

-- login to the bus
conn1AtBus1WithOrb1:loginByPassword("conn1", "conn1")
conn2AtBus1WithOrb1:loginByPassword("conn2", "conn2")
connAtBus2WithOrb1:loginByPassword("demo", "demo")
connAtBus1WithOrb2:loginByPassword("demo", "demo")

-- offer the service
cothread.schedule(coroutine.create(function()
  multiplexer:setCurrentConnection(conn1AtBus1WithOrb1)
  conn1AtBus1WithOrb1.offers:registerService(component1.IComponent, {
    {name="offer.domain",value="OpenBus Demos"}, -- provided property
  })
end))
cothread.schedule(coroutine.create(function()
  multiplexer:setCurrentConnection(conn2AtBus1WithOrb1)
  conn2AtBus1WithOrb1.offers:registerService(component1.IComponent, {
    {name="offer.domain",value="OpenBus Demos"}, -- provided property
  })
end))
multiplexer:setCurrentConnection(connAtBus2WithOrb1)
connAtBus2WithOrb1.offers:registerService(component1.IComponent, {
  {name="offer.domain",value="OpenBus Demos"}, -- provided property
})
connAtBus1WithOrb2.offers:registerService(component2.IComponent, {
  {name="offer.domain",value="OpenBus Demos"}, -- provided property
})
