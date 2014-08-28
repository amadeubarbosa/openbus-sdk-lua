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

bushost, busport, verbose = ...
require "openbus.test.configs"

syskey = assert(openbus.readKeyFile(syskey))

local thread = coroutine.running()
local userdata = io.stdout
local sleep = cothread.delay

local sysex = giop.SystemExceptionIDs

local entity = nil -- defined later
local orb = openbus.initORB()
local OpenBusContext = orb.OpenBusContext
assert(OpenBusContext.orb == orb)
local conns = {}

local function catcherr(...)
  local ok, err = pcall(...)
  assert(not ok)
  return err
end

local loginways = {
  loginByPassword = function() return user, password end,
  loginByCertificate = function() return system, syskey end,
  loginByCallback = function()
    return function ()
      return "SharedAuth", { -- dummy login process object
        login = function()
          return {
            id = "60D57646-33A4-4108-88DD-AE9B7A9E3C7A",
            entity = system,
          }, 1
        end,
        cancel = function () end,
      },
      "fake secret"
    end
  end,
}
local function assertlogged(conn)
  -- check constant attributes
  assert(conn.orb == orb)
  -- check logged in only attributes
  assert(conn.login ~= nil)
  assert(conn.login.entity == entity)
  assert(uuid.isvalid(conn.login.id))
  assert(uuid.isvalid(conn.busid))
  local loginid = conn.login.id
  local busid = conn.busid
  -- check the attempt to login again
  for opname, getparams in pairs(loginways) do
    local ex = catcherr(conn[opname], conn, getparams())
    assert(ex._repid == libidl.types.AlreadyLoggedIn, ex)
    assert(conn.login.entity == entity)
    assert(conn.login.id == loginid)
    assert(conn.busid == busid)
  end
  -- check the success of 'startSharedAuth'
  conn:cancelSharedAuth(conn:startSharedAuth())
  -- check the login is valid to perform calls
  assert(type(conn:getAllServices()) == "table")
  return conn
end

local function assertlogoff(conn, invalid)
  -- check constant attributes
  assert(conn.orb == orb)
  -- check logged in only attributes
  assert(conn.login == nil)
  assert(conn.busid == nil)
  if not invalid then
    -- check the attempt to logoff again
    assert(conn:logout() == false)
    -- check the failure of 'startSharedAuth'
    local ex = catcherr(conn.startSharedAuth, conn)
    assert(ex._repid == sysex.NO_PERMISSION)
    assert(ex.completed == "COMPLETED_NO")
    assert(ex.minor == idl.const.services.access_control.NoLoginCode)
    -- check the login is invalid to perform calls
    local ex = catcherr(conn.getAllServices, conn)
    assert(ex._repid == sysex.NO_PERMISSION)
    assert(ex.completed == "COMPLETED_NO")
    assert(ex.minor == idl.const.services.access_control.NoLoginCode)
  end
  return conn
end

log:TEST(true, "ConnectionManager::createConnection")

do log:TEST "connect with invalid host"
  for _, invalid in ipairs{true,false,123,{},error,thread,userdata} do
    local badtype = type(invalid)
    local ex = catcherr(assistant.create, {orb=orb, bushost=invalid, busport=busport})
    assert(ex:match("bad field 'bushost' to 'create' %(expected string, got "..badtype.."%)$"))
  end
end

do log:TEST "connect with invalid port"
  for _, invalid in ipairs{true,false,{},error,thread,userdata} do
    local badtype = type(invalid)
    local ex = catcherr(assistant.create, {orb=orb, bushost=bushost, busport=invalid})
    assert(ex:match("bad field 'busport' to 'create' %(expected number|string, got "..badtype.."%)$"))
  end
end

do log:TEST "connect to unavailable host"
  local conn = assistant.create{orb=orb, bushost="unavailable", busport=busport}
  for op, params in pairs(loginways) do
    local ex = catcherr(conn[op], conn, params())
    assert(ex._repid == sysex.TRANSIENT)
    assert(ex.completed == "COMPLETED_NO")
  end
end

do log:TEST "connect to unavailable port"
  local conn = assistant.create{orb=orb, bushost=bushost, busport=0}
  for op, params in pairs(loginways) do
    local ex = catcherr(conn[op], conn, params())
    assert(ex._repid == sysex.TRANSIENT)
    assert(ex.completed == "COMPLETED_NO")
  end
end

do log:TEST "connect to bus"
  for i = 1, 2 do
    conns[i] = assertlogoff(assistant.create{orb=orb, bushost=bushost, busport=busport})
  end
end

--do return orb:shutdown() end

-- create a valid key to be used as a wrong key in the tests below.
-- the generation of this key is too time consuming and may delay the renewer
-- thread of the admin account to renew the admin login in time.
local WrongKey = openbus.newKey()
-- login as admin and provide additional functionality for the test
local invalidate, shutdown, leasetime do
  local orb = openbus.initORB()
  local OpenBusContext = orb.OpenBusContext
  local conn = OpenBusContext:createConnection(bushost, busport)
  conn:loginByPassword(admin, admpsw)
  OpenBusContext:setDefaultConnection(conn)
  leasetime = conn.AccessControl:renew()
  function invalidate(loginId)
    OpenBusContext:getLoginRegistry():invalidateLogin(loginId)
  end
  function shutdown()
    conn:logout()
    orb:shutdown()
  end
end

for _, connOp in ipairs({"DefaultConnection", "CurrentConnection"}) do
  local connIdx = 0
  repeat
    
    log:TEST(true, "Connection::loginBy* (",connOp,"=",connIdx==0 and "nil" or "conn"..connIdx,")")
    
    do log:TEST "login with invalid entity"
      local conn = conns[1]
      for _, invalid in ipairs{nil,true,false,123,{},error,thread,userdata} do
        local badtype = type(invalid)
        for _, op in ipairs{"loginByPassword", "loginByCertificate"} do
          local ex = catcherr(conn[op], conn, invalid, select(2, loginways[op]()))
          assert(ex:match("bad argument #1 to '"..op.."' %(expected string, got "..badtype.."%)$"))
          assertlogoff(conn)
        end
      end
    end
    
    do log:TEST "login with invalid password"
      local conn = conns[1]
      for _, invalid in ipairs{nil,true,false,123,{},error,thread,userdata} do
        local badtype = type(invalid)
        local ex = catcherr(conn.loginByPassword, conn, user, invalid)
        assert(ex:match("bad argument #2 to 'loginByPassword' %(expected string, got "..badtype.."%)$"))
        assertlogoff(conn)
      end
    end
    
    do log:TEST "login with invalid private key"
      local conn = conns[1]
      for _, invalid in ipairs{nil,true,false,123,"key",{},error,thread} do
        local badtype = type(invalid)
        local ex = catcherr(conn.loginByCertificate, conn, system, invalid)
        assert(ex:match("bad argument #2 to 'loginByCertificate' %(expected userdata, got "..badtype.."%)$"))
        assertlogoff(conn)
      end
    end
    
    do log:TEST "login with wrong password"
      local conn = conns[1]
      local ex = catcherr(conn.loginByPassword, conn, user, "WrongPassword")
      assert(ex._repid == idl.types.services.access_control.AccessDenied)
      assertlogoff(conn)
    end
    
    do log:TEST "login with entity without certificate"
      local conn = conns[1]
      local ex = catcherr(conn.loginByCertificate, conn, "NoCertif.", syskey)
      assert(ex._repid == idl.types.services.access_control.MissingCertificate)
      assert(ex.entity == "NoCertif.")
      assertlogoff(conn)
    end
    
    do log:TEST "login with wrong private key"
      local conn = conns[1]
      local ex = catcherr(conn.loginByCertificate, conn, system, WrongKey)
      assert(ex._repid == idl.types.services.access_control.AccessDenied)
      assertlogoff(conn)
    end
    
    do
      local function testlogin(conn, op, getparams)
        
        log:TEST("successful Connection::",op)
        if getparams == nil then getparams = loginways[op] end
        -- first login
        conn[op](conn, getparams())
        assertlogged(conn)
        local loginid = conn.login.id
        local busid = conn.busid
        -- first logout
        conn:logout()
        assertlogoff(conn)
        -- second login
        conn[op](conn, getparams())
        assertlogged(conn)
        assert(conn.login.id ~= loginid)
        assert(conn.busid == busid)
        loginid = conn.login.id
        -- automatic login renew
        sleep(2*leasetime)
        assertlogged(conn)
        assert(conn.login.id == loginid)
        assert(conn.busid == busid)
        
        for otherIdx, other in ipairs(conns) do
          if other.login == nil then
            
            log:TEST(true, "Connection::loginBySharedAuth (from=Connection::",op,")")
            
            do log:TEST "login with wrong secret"
              local attempt = conn:startSharedAuth()
              local ex = catcherr(other.loginByCallback, other, function ()
                return "SharedAuth", attempt, "WrongSecret"
              end)
              assert(ex._repid == idl.types.services.access_control.AccessDenied)
              assertlogoff(other)
              assertlogged(conn)
            end
            do log:TEST "login with canceled attempt"
              local attempt, secret = conn:startSharedAuth()
              conn:cancelSharedAuth(attempt)
              local ex = catcherr(other.loginByCallback, other, function ()
                return "SharedAuth", attempt, secret
              end)
              assert(ex._repid == libidl.types.InvalidLoginProcess)
              assertlogoff(other)
              assertlogged(conn)
            end
            do log:TEST "login with expired attempt"
              local attempt, secret = conn:startSharedAuth()
              sleep(2*leasetime)
              local ex = catcherr(other.loginByCallback, other, function ()
                return "SharedAuth", attempt, secret
              end)
              assert(ex._repid == libidl.types.InvalidLoginProcess)
              assertlogoff(other)
              assertlogged(conn)
            end
            do
              testlogin(other, "loginByCallback", function()
                return function ()
                  return "SharedAuth", conn:startSharedAuth()
                end
              end)
              assertlogged(conn)
            end
            
            log:TEST(false)
            
            break
          end
        end

        log:TEST(true, "Connection::onInvalidLogin (how=",op,")")
        
        do log:TEST "reconnect"
          -- during renew
          invalidate(conn.login.id)
          sleep(leasetime+2) -- wait renew
          assertlogged(conn)
          -- during call
          invalidate(conn.login.id)
          conn:getAllServices()
          assertlogged(conn)
        end
        
        log:TEST(false)
        
        conn:logout()
        assertlogoff(conn)
      end
      
      entity = user; testlogin(conns[1], "loginByPassword")
      entity = system; testlogin(conns[1], "loginByCertificate")
    end
    
    log:TEST(false)
    
    assert(OpenBusContext["get"..connOp](OpenBusContext) == conns[connIdx])
    connIdx = connIdx+1
    local nextConn = conns[connIdx]
    OpenBusContext["set"..connOp](OpenBusContext, nextConn)
  until nextConn == nil
end

log:TEST(false)

orb:shutdown()
shutdown()
