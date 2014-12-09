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
local libidl = require "openbus.idl"
local idl = require "openbus.core.idl"
local msg = require "openbus.util.messages"
local log = require "openbus.util.logger"
local util = require "openbus.util.server"

local sysex = giop.SystemExceptionIDs
local LoginObserverRepId = idl.types.services.access_control.LoginObserver

require "openbus.test.util"

setorbcfg(...)

busref = assert(util.readfrom(busref, "r"))

local smalltime = .1
local connprops = { accesskey = openbus.newKey() }

-- login as admin and provide additional functionality for the test
local invalidate, shutdown do
  local orb = openbus.initORB(orbcfg)
  local OpenBusContext = orb.OpenBusContext
  local busref = orb:newproxy(busref, nil, "::scs::core::IComponent")
  local conn = OpenBusContext:connectByReference(busref)
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

local orb = openbus.initORB(orbcfg)
local OpenBusContext = orb.OpenBusContext
assert(OpenBusContext.orb == orb)
local busref = orb:newproxy(busref, nil, "::scs::core::IComponent")



do log:TEST("Get invalid login notification while performing a call")
  local conn = OpenBusContext:connectByReference(busref, connprops)
  conn:loginByPassword(user, password, domain)
  OpenBusContext:setDefaultConnection(conn)
  
  invalidate(conn.login.id)
  
  local prx = orb:newproxy(servant())
  local ok, ex = pcall(prx.entityLogout, prx, {id="???",entity="???"})
  if not ok then
    assert(ex._repid == sysex.NO_PERMISSION)
    assert(ex.completed == "COMPLETED_NO")
    assert(ex.minor == idl.const.services.access_control.NoLoginCode)
  end
  
  assert(conn.login == nil)
  OpenBusContext:setDefaultConnection(nil)
end

do log:TEST("Get invalid login notification while dispathing a call")
  local conn = OpenBusContext:connectByReference(busref, connprops)
  conn:loginByPassword(user, password, domain)
  OpenBusContext:setDefaultConnection(conn)
  
  local ior = tostring(orb:newservant({}, nil, "CORBA::InterfaceDef"))
  local pxy = newproxy(ior, nil, "CORBA::InterfaceDef")

  invalidate(conn.login.id)
  
  local ok, ex = pcall(pxy._non_existent, pxy)
  assert(not ok)
  assert(ex._repid == sysex.NO_PERMISSION)
  assert(ex.completed == "COMPLETED_NO")
  assert(ex.minor == idl.const.services.access_control.UnknownBusCode)
  
  assert(conn.login == nil)
  OpenBusContext:setDefaultConnection(nil)
end



do log:TEST("Relog while performing a call")
  local conn = OpenBusContext:connectByReference(busref, connprops)
  conn:loginByPassword(user, password, domain)
  OpenBusContext:setDefaultConnection(conn)
  
  function conn:onInvalidLogin(login)
    local ok, ex = pcall(conn.loginByPassword, conn, user, password, domain)
    if not ok then
      assert(ex._repid == libidl.types.AlreadyLoggedIn)
    end
  end

  local prx = orb:newproxy(servant())
  
  invalidate(conn.login.id)
  
  prx:entityLogout{id="???",entity="???"}
  
  conn:logout()
  OpenBusContext:setDefaultConnection(nil)
end

do log:TEST("Relog while dispathing a call")
  local conn = OpenBusContext:connectByReference(busref, connprops)
  conn:loginByPassword(user, password, domain)
  OpenBusContext:setDefaultConnection(conn)
  
  function conn:onInvalidLogin(login)
    local ok, ex = pcall(conn.loginByPassword, conn, user, password, domain)
    if not ok then
      assert(ex._repid == libidl.types.AlreadyLoggedIn)
    end
  end
  
  local ior = tostring(orb:newservant({entityLogout = function() end}, nil,
                                      LoginObserverRepId))
  local pxy = newproxy(ior, nil, LoginObserverRepId)
  
  invalidate(conn.login.id)
  
  pxy:entityLogout{id="???",entity="???"}
  
  conn:logout()
  OpenBusContext:setDefaultConnection(nil)
end

orb:shutdown()
shutdown()
