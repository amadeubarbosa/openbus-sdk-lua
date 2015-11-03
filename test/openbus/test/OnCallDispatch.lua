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

local sysex = giop.SystemExceptionIDs
local LoginObserverRepId = idl.types.services.access_control.LoginObserver

bushost, busport, verbose = ...
require "openbus.test.configs"

local smalltime = .1
local connprops = { accesskey = openbus.newKey() }

-- login as admin and provide additional functionality for the test
local invalidate, shutdown, busid, caller do
  local orb = openbus.initORB()
  local OpenBusContext = orb.OpenBusContext
  local conn = OpenBusContext:createConnection(bushost, busport)
  conn:loginByPassword(admin, admpsw)
  busid = conn.busid
  caller = conn.login
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



do log:TEST("Return no connections")
  function OpenBusContext:onCallDispatch(bus, login, objkey, opname, ...)
    assert(bus == busid)
    assert(login == caller.id)
    assert(objkey == "DummyObject")
    assert(opname == "_non_existent")
    assert(select("#", ...) == 0)
  end

  local srv = orb:newservant({}, "DummyObject", "CORBA::InterfaceDef")
  local ior = tostring(srv)
  local pxy = newproxy(ior, nil, "CORBA::InterfaceDef")

  local ok, ex = pcall(pxy._non_existent, pxy)
  assert(not ok)
  assert(ex._repid == sysex.NO_PERMISSION)
  assert(ex.completed == "COMPLETED_NO")
  assert(ex.minor == idl.const.services.access_control.UnknownBusCode)

  srv:__deactivate()
end

do log:TEST("Return disconnected connection")
  local conn = OpenBusContext:createConnection(bushost, busport, connprops)

  function OpenBusContext:onCallDispatch(bus, login, objkey, opname, ...)
    assert(bus == busid)
    assert(login == caller.id)
    assert(objkey == "DummyObject")
    assert(opname == "_non_existent")
    assert(select("#", ...) == 0)
    return conn
  end

  local srv = orb:newservant({}, "DummyObject", "CORBA::InterfaceDef")
  local ior = tostring(srv)
  local pxy = newproxy(ior, nil, "CORBA::InterfaceDef")

  local ok, ex = pcall(pxy._non_existent, pxy)
  assert(not ok)
  assert(ex._repid == sysex.NO_PERMISSION)
  assert(ex.completed == "COMPLETED_NO")
  assert(ex.minor == idl.const.services.access_control.UnknownBusCode)

  srv:__deactivate()
end

do log:TEST("Default connection fallback")
  local conn = OpenBusContext:createConnection(bushost, busport, connprops)
  conn:loginByPassword(user, password)
  OpenBusContext:setDefaultConnection(conn)

  function OpenBusContext:onCallDispatch(bus, login, objkey, opname, ...)
    assert(bus == busid)
    assert(login == caller.id)
    assert(objkey == "DummyObject")
    assert(opname == "_non_existent")
    assert(select("#", ...) == 0)
  end

  local srv = orb:newservant({}, "DummyObject", "CORBA::InterfaceDef")
  local ior = tostring(srv)
  local pxy = newproxy(ior, nil, "CORBA::InterfaceDef")
  
  assert(pxy:_non_existent() == false)
  
  srv:__deactivate()

  assert(conn:logout())
  OpenBusContext:setDefaultConnection(nil)
end

do log:TEST("Return connection to another bus")
  local conn = OpenBusContext:createConnection(bushost, busport, connprops)
  conn:loginByPassword(user, password)
  OpenBusContext:setDefaultConnection(conn)

  local conn2 = OpenBusContext:createConnection(bus2host, bus2port, connprops)
  conn2:loginByPassword(user, password)
  function OpenBusContext:onCallDispatch(bus, login, objkey, opname, ...)
    assert(bus == busid)
    assert(login == caller.id)
    assert(objkey == "DummyObject")
    assert(opname == "_non_existent")
    assert(select("#", ...) == 0)
    return conn2
  end

  local srv = orb:newservant({}, "DummyObject", "CORBA::InterfaceDef")
  local ior = tostring(srv)
  local pxy = newproxy(ior, nil, "CORBA::InterfaceDef")
  
  local ok, ex = pcall(pxy._non_existent, pxy)
  assert(not ok)
  assert(ex._repid == sysex.NO_PERMISSION)
  assert(ex.completed == "COMPLETED_NO")
  assert(ex.minor == idl.const.services.access_control.UnknownBusCode)
  
  srv:__deactivate()

  assert(conn2:logout())
  assert(conn:logout())
  OpenBusContext:setDefaultConnection(nil)
end

do log:TEST("Raise error")
  function OpenBusContext:onCallDispatch(bus, login, objkey, opname, ...)
    assert(bus == busid)
    assert(login == caller.id)
    assert(objkey == "DummyObject")
    assert(opname == "_non_existent")
    assert(select("#", ...) == 0)
    error("INTENTIONAL ERROR")
  end

  local srv = orb:newservant({}, "DummyObject", "CORBA::InterfaceDef")
  local ior = tostring(srv)
  local pxy = newproxy(ior, nil, "CORBA::InterfaceDef")
  
  local ok, ex = pcall(pxy._non_existent, pxy)
  assert(not ok)
  assert(ex._repid == sysex.UNKNOWN)
  
  srv:__deactivate()

end

do log:TEST("Raise CORBA system exception")
  function OpenBusContext:onCallDispatch(bus, login, objkey, opname, ...)
    assert(bus == busid)
    assert(login == caller.id)
    assert(objkey == "DummyObject")
    assert(opname == "_non_existent")
    assert(select("#", ...) == 0)
    error{
      _repid = sysex.NO_PERMISSION,
      completed = "COMPLETED_YES",
      minor = 1234,
    }
  end

  local srv = orb:newservant({}, "DummyObject", "CORBA::InterfaceDef")
  local ior = tostring(srv)
  local pxy = newproxy(ior, nil, "CORBA::InterfaceDef")
  
  local ok, ex = pcall(pxy._non_existent, pxy)
  assert(not ok)
  assert(ex._repid == sysex.NO_PERMISSION)
  assert(ex.completed == "COMPLETED_YES")
  assert(ex.minor == 1234)
  
  srv:__deactivate()

end



orb:shutdown()
shutdown()
