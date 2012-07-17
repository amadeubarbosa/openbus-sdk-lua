local _G = require "_G"
local assert = _G.assert
local error = _G.error
local ipairs = _G.ipairs
local pairs = _G.pairs
local pcall = _G.pcall
local type = _G.type
local unpack = _G.unpack
local coroutine = require "coroutine"
local string = require "string"
local io = require "io"
local uuid = require "uuid"
local pubkey = require "lce.pubkey"
local giop = require "oil.corba.giop"
local cothread = require "cothread"
local openbus = require "openbus"
local idl = require "openbus.core.idl"
local msg = require "openbus.util.messages"
local log = require "openbus.util.logger"

local sysex = giop.SystemExceptionIDs
local LoginObserverRepId = idl.types.services.access_control.LoginObserver

bushost, busport, verbose = ...
require "openbus.util.testcfg"

local smalltime = .1

-- login as admin and provide additional functionality for the test
local invalidate, shutdown do
  local manager = openbus.initORB().OpenBusConnectionManager
  local conn = manager:createConnection(bushost, busport)
  local logins = conn.logins
  conn:loginByPassword(admin, admpsw)
  manager:setDefaultConnection(conn)
  local orb = manager.orb
  openbus.newthread(orb.run, orb)
  function invalidate(loginId)
    logins:invalidateLogin(loginId)
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
local manager = orb.OpenBusConnectionManager
assert(manager.orb == orb)
local connprops = { privatekey = pubkey.create(idl.const.EncryptedBlockSize) }



do log:TEST("Get invalid login notification while performing a call")
  local conn = manager:createConnection(bushost, busport, connprops)
  conn:loginByPassword(user, password)
  manager:setDefaultConnection(conn)
  
  invalidate(conn.login.id)
  
  local prx = orb:newproxy(servant())
  local ok, ex = pcall(prx.entityLogout, prx, {id="???",entity="???"})
  if not ok then
    assert(ex._repid == sysex.NO_PERMISSION)
    assert(ex.completed == "COMPLETED_NO")
    assert(ex.minor == idl.const.services.access_control.NoLoginCode)
  end
  
  assert(conn.login == nil)
  manager:setDefaultConnection(nil)
end

do log:TEST("Get invalid login notification while dispathing a call")
  local conn = manager:createConnection(bushost, busport, connprops)
  conn:loginByPassword(user, password)
  manager:setDefaultConnection(conn)
  
  local ior = tostring(orb:newservant({}, nil, "CORBA::InterfaceDef"))
  local pxy = newproxy(ior, nil, "CORBA::InterfaceDef")

  local orb = manager.orb
  openbus.newthread(orb.run, orb)
  
  invalidate(conn.login.id)
  
  local ok, ex = pcall(pxy._non_existent, pxy)
  assert(not ok)
  assert(ex._repid == sysex.NO_PERMISSION)
  assert(ex.completed == "COMPLETED_NO")
  assert(ex.minor == idl.const.services.access_control.UnknownBusCode)
  
  orb:shutdown()
  
  assert(conn.login == nil)
  manager:setDefaultConnection(nil)
end



do log:TEST("Relog while performing a call")
  local conn = manager:createConnection(bushost, busport, connprops)
  conn:loginByPassword(user, password)
  manager:setDefaultConnection(conn)
  
  function conn:onInvalidLogin(login)
    local ok, ex = pcall(conn.loginByPassword, conn, user, password)
    if not ok then
      assert(ex:find(msg.AlreadyLoggedIn, 1, true) == 1+#ex-#msg.AlreadyLoggedIn, ex)
    end
  end

  local prx = orb:newproxy(servant())
  
  invalidate(conn.login.id)
  
  prx:entityLogout{id="???",entity="???"}
  
  assert(conn:logout())
  manager:setDefaultConnection(nil)
end

do log:TEST("Relog while dispathing a call")
  local conn = manager:createConnection(bushost, busport, connprops)
  conn:loginByPassword(user, password)
  manager:setDefaultConnection(conn)
  
  function conn:onInvalidLogin(login)
    local ok, ex = pcall(conn.loginByPassword, conn, user, password)
    if not ok then
      assert(ex:find(msg.AlreadyLoggedIn, 1, true) == 1+#ex-#msg.AlreadyLoggedIn, ex)
    end
  end
  
  local ior = tostring(orb:newservant({entityLogout = function() end}, nil,
                                      LoginObserverRepId))
  local pxy = newproxy(ior, nil, LoginObserverRepId)
  
  local orb = manager.orb
  openbus.newthread(orb.run, orb)
  
  invalidate(conn.login.id)
  
  pxy:entityLogout{id="???",entity="???"}
  
  orb:shutdown()
  
  assert(conn:logout())
  manager:setDefaultConnection(nil)
end

shutdown()
