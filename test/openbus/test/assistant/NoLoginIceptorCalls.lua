local _G = require "_G"
local assert = _G.assert
local error = _G.error
local ipairs = _G.ipairs
local pairs = _G.pairs
local pcall = _G.pcall
local type = _G.type
local coroutine = require "coroutine"
local string = require "string"
local io = require "io"
local uuid = require "uuid"
local giop = require "oil.corba.giop"
local cothread = require "cothread"
local openbus = require "openbus"
local assistant = require "openbus.assistant2"
local libidl = require "openbus.idl"
local idl = require "openbus.core.idl"
local msg = require "openbus.util.messages"
local log = require "openbus.util.logger"

local sysex = giop.SystemExceptionIDs
local LoginObserverRepId = idl.types.services.access_control.LoginObserver

bushost, busport, verbose = ...
require "openbus.test.configs"

local accesskey = openbus.newKey()

-- login as admin and provide additional functionality for the test
local invalidate, shutdown do
  local orb = openbus.initORB()
  local OpenBusContext = orb.OpenBusContext
  local conn = OpenBusContext:createConnection(bushost, busport)
  conn:loginByPassword(admin, admpsw, domain)
  OpenBusContext:setDefaultConnection(conn)
  function invalidate(loginId)
    OpenBusContext:getLoginRegistry():invalidateLogin(loginId)
  end
  function newproxy(...)
    return orb:newproxy(...)
  end
  function servant(func)
    if func == nil then func = function() end end
    return tostring(orb:newservant({entityLogout=func}, nil,
                                   LoginObserverRepId)),
           nil,
           LoginObserverRepId
  end
  function shutdown()
    conn:logout()
    orb:shutdown()
  end
end

local orb = openbus.initORB()
local OpenBusContext = orb.OpenBusContext
assert(OpenBusContext.orb == orb)



do log:TEST("Relog while performing a call")
  local conn = assistant.create{
    orb = orb,
    bushost = bushost,
    busport = busport,
    accesskey = accesskey,
  }
  conn:loginByPassword(user, password, domain)
  OpenBusContext:setDefaultConnection(conn.connection)
  
  invalidate(conn.login.id)
  
  local prx = orb:newproxy(servant())
  prx:entityLogout{id="???",entity="???"}
  
  OpenBusContext:setDefaultConnection(nil)
  assert(conn:logout())
end

do log:TEST("Relog while dispathing a call")
  local conn = assistant.create{
    orb = orb,
    bushost = bushost,
    busport = busport,
    accesskey = accesskey,
  }
  conn:loginByPassword(user, password, domain)
  OpenBusContext:setDefaultConnection(conn.connection)
  
  local ior = tostring(orb:newservant({}, nil, "CORBA::InterfaceDef"))
  local pxy = newproxy(ior, nil, "CORBA::InterfaceDef")

  invalidate(conn.login.id)
  
  local res = pxy:_non_existent()
  assert(res == false)
  
  OpenBusContext:setDefaultConnection(nil)
  assert(conn:logout())
end

orb:shutdown()
shutdown()
