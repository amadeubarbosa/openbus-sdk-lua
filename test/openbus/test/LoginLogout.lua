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

require "openbus.test.util"

setorbcfg(...)

busref = assert(util.readfrom(busref, "r"))
bus2ref = assert(util.readfrom(bus2ref, "r"))
syskey = assert(openbus.readKeyFile(syskey))

local thread = coroutine.running()
local userdata = io.stdout
local sleep = cothread.delay

local sysex = giop.SystemExceptionIDs

local entity = nil -- defined later
local orb = openbus.initORB(orbcfg)
local OpenBusContext = orb.OpenBusContext
assert(OpenBusContext.orb == orb)
local conns = {}
local busid
local otherBusConn

local function catcherr(...)
  local ok, err = pcall(...)
  assert(not ok)
  return err
end

local callwithin do
  local function continuation(backup, ...)
    OpenBusContext:setCurrentConnection(backup)
    return ...
  end
  function callwithin(conn, func, ...)
    local backup = OpenBusContext:setCurrentConnection(conn)
    return continuation(backup, func(...))
  end
end

local loginways = {
  loginByPassword = function() return user, password, domain end,
  loginByCertificate = function() return system, syskey end,
  loginBySharedAuth = function()
    return {
      busid = busid,
      attempt = { -- dummy login process object
        login = function()
          return {
            id = "60D57646-33A4-4108-88DD-AE9B7A9E3C7A",
            entity = system,
          }, 1
        end,
        cancel = function () end,
      },
      secret = "fake secret",
      cancel = function () end,
    }
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
  -- check the failure of 'startSharedAuth'
  assert(conn:startSharedAuth():cancel() == true)
  -- check the login is valid to perform calls
  local OfferRegistry = callwithin(conn, OpenBusContext.getOfferRegistry, OpenBusContext)
  assert(OfferRegistry ~= nil)
  callwithin(conn, OfferRegistry.findServices, OfferRegistry, {})
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
    assert(conn:logout() == true)
    -- check the failure of 'startSharedAuth'
    local ex = catcherr(conn.startSharedAuth, conn)
    assert(ex._repid == sysex.NO_PERMISSION)
    assert(ex.completed == "COMPLETED_NO")
    assert(ex.minor == idl.const.services.access_control.NoLoginCode)
    -- check the login is invalid to perform calls
    local ex = callwithin(conn, catcherr, OpenBusContext.getOfferRegistry, OpenBusContext)
    assert(ex._repid == sysex.NO_PERMISSION)
    assert(ex.completed == "COMPLETED_NO")
    assert(ex.minor == idl.const.services.access_control.NoLoginCode)
  end
  return conn
end

log:TEST(true, "ConnectionManager::connectByAddress")

do log:TEST "connect with invalid host"
  for _, invalid in ipairs{true,false,123,{},error,thread,userdata} do
    local badtype = type(invalid)
    local ex = catcherr(OpenBusContext.connectByAddress, OpenBusContext, invalid, busport)
    assert(ex:match("bad argument #2 to 'connectByAddress' %(expected string, got "..badtype.."%)$"))
  end
end

do log:TEST "connect with invalid port"
  for _, invalid in ipairs{true,false,{},error,thread,userdata} do
    local badtype = type(invalid)
    local ex = catcherr(OpenBusContext.connectByAddress, OpenBusContext, bushost, invalid)
    assert(ex:match("bad argument #3 to 'connectByAddress' %(expected number|string, got "..badtype.."%)$"))
  end
end

do log:TEST "connect with invalid properties"
  for _, invalid in ipairs{true,false,123,"nolegacy",error,thread,userdata} do
    local badtype = type(invalid)
    local ex = catcherr(OpenBusContext.connectByAddress, OpenBusContext, bushost, busport, invalid)
    assert(ex:match("bad argument #4 to 'connectByAddress' %(expected nil|table, got "..badtype.."%)$"))
  end
end

do log:TEST "connect to unavailable host"
  local conn = OpenBusContext:connectByAddress("unavailable", busport)
  for op, params in pairs(loginways) do
    local ex = catcherr(conn[op], conn, params())
    if orbcfg and orbcfg.options.security == "required" then
      assert(ex._repid == sysex.NO_PERMISSION)
      assert(ex.completed == "COMPLETED_NO")
    else
      assert(ex._repid == sysex.TRANSIENT)
      assert(ex.completed == "COMPLETED_NO")
    end
  end
end

do log:TEST "connect to unavailable port"
  local conn = OpenBusContext:connectByAddress(bushost, 0)
  for op, params in pairs(loginways) do
    local ex = catcherr(conn[op], conn, params())
    if orbcfg and orbcfg.options.security == "required" then
      assert(ex._repid == sysex.NO_PERMISSION)
      assert(ex.completed == "COMPLETED_NO")
    else
      assert(ex._repid == sysex.TRANSIENT)
      assert(ex.completed == "COMPLETED_NO")
    end
  end
end

do log:TEST "connect to bus"
  local bus = orb:newproxy(busref, nil, "::scs::core::IComponent")
  local bus2 = orb:newproxy(bus2ref, nil, "::scs::core::IComponent")
  for i = 1, 2 do
    conns[i] = assertlogoff(OpenBusContext:connectByReference(bus))
  end
  otherBusConn = OpenBusContext:connectByReference(bus2)
end

-- create a valid key to be used as a wrong key in the tests below.
-- the generation of this key is too time consuming and may delay the renewer
-- thread of the admin account to renew the admin login in time.
local WrongKey = openbus.newKey()
-- login as admin and provide additional functionality for the test
local invalidate, shutdown, leasetime do
  local orb = openbus.initORB(orbcfg)
  local OpenBusContext = orb.OpenBusContext
  local busref = orb:newproxy(busref, nil, "::scs::core::IComponent")
  local conn = OpenBusContext:connectByReference(busref)
  conn:loginByPassword(admin, admpsw, domain)
  OpenBusContext:setDefaultConnection(conn)
  busid = conn.busid
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
        local ex = catcherr(conn.loginByPassword, conn, user, invalid, domain)
        assert(ex:match("bad argument #2 to 'loginByPassword' %(expected string, got "..badtype.."%)$"))
        assertlogoff(conn)
      end
    end
    
    do log:TEST "login with invalid domain"
      local conn = conns[1]
      for _, invalid in ipairs{nil,true,false,123,{},error,thread,userdata} do
        local badtype = type(invalid)
        local ex = catcherr(conn.loginByPassword, conn, user, password, invalid)
        assert(ex:match("bad argument #3 to 'loginByPassword' %(expected string, got "..badtype.."%)$"))
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
      local ex = catcherr(conn.loginByPassword, conn, user, "WrongPassword", domain)
      assert(ex._repid == idl.types.services.access_control.AccessDenied)
      assertlogoff(conn)
    end
    
    do log:TEST "login with unknown domain"
      local conn = conns[1]
      local ex = catcherr(conn.loginByPassword, conn, user, password, "UnknownDomain")
      assert(ex._repid == idl.types.services.access_control.UnknownDomain)
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
        assert(conn:logout() == true)
        assertlogoff(conn)
        -- second login
        local function relogin()
          conn[op](conn, getparams())
          assertlogged(conn)
          assert(conn.login.id ~= loginid)
          assert(conn.busid == busid)
          loginid = conn.login.id
        end
        relogin()
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
              attempt.secret = "WrongSecret" -- this is not allowed by the API
              local ex = catcherr(other.loginBySharedAuth, other, attempt)
              assert(ex._repid == idl.types.services.access_control.AccessDenied)
              assertlogoff(other)
              assertlogged(conn)
            end
            do log:TEST "login with canceled attempt"
              local attempt = conn:startSharedAuth()
              attempt:cancel()
              local ex = catcherr(other.loginBySharedAuth, other, attempt)
              assert(ex._repid == libidl.types.InvalidLoginProcess)
              assertlogoff(other)
              assertlogged(conn)
            end
            do log:TEST "login with expired attempt"
              local attempt = conn:startSharedAuth()
              sleep(2*leasetime)
              local ex = catcherr(other.loginBySharedAuth, other, attempt)
              assert(ex._repid == libidl.types.InvalidLoginProcess)
              assertlogoff(other)
              assertlogged(conn)
            end
            do log:TEST "login with wrong bus"
              otherBusConn:loginByPassword(user, password, domain)
              local attempt = otherBusConn:startSharedAuth()
              assert(otherBusConn:logout() == true)
              local ex = catcherr(other.loginBySharedAuth, other, attempt)
              assert(ex._repid == libidl.types.WrongBus)
              assertlogoff(other)
              assertlogged(conn)
            end
            do
              testlogin(other, "loginBySharedAuth", function()
                return conn:startSharedAuth()
              end)
              assertlogged(conn)
            end
            
            log:TEST(false)
            
            break
          end
        end
        
        log:TEST(true, "Connection::onInvalidLogin (how=",op,")")
        
        local OfferRegistry = callwithin(conn, OpenBusContext.getOfferRegistry, OpenBusContext)
        local called
        local function assertCallback(self, login)
          assert(self == conn)
          assert(login.id == loginid)
          assert(login.entity == entity)
          assertlogoff(conn, "invalid login")
          called = true
        end
        
        do log:TEST "become invalid"
          conn.onInvalidLogin = assertCallback
          -- during renew
          assert(called == nil)
          invalidate(conn.login.id)
          sleep(leasetime+2) -- wait renew
          assert(called); called = nil
          assertlogoff(conn)
          relogin()
          -- during call
          assert(called == nil)
          invalidate(conn.login.id)
          local ex = callwithin(conn, catcherr, OfferRegistry.findServices, OfferRegistry, {})
          assert(ex._repid == sysex.NO_PERMISSION)
          assert(ex.completed == "COMPLETED_NO")
          assert(ex.minor == idl.const.services.access_control.NoLoginCode)
          assert(called); called = nil
          assertlogoff(conn)
          relogin()
          -- during logout
          assert(called == nil)
          invalidate(conn.login.id)
          assert(conn:logout() == true)
          assert(called == nil)
          assertlogoff(conn)
          relogin()
        end
        
        do log:TEST "reconnect"
          function conn:onInvalidLogin(login)
            assertCallback(self, login)
            local ok, ex = pcall(relogin)
            if not ok then
              assert(ex._repid == libidl.types.AlreadyLoggedIn)
            end
            assertlogged(self)
          end
          -- during renew
          assert(called == nil)
          invalidate(conn.login.id)
          sleep(leasetime+2) -- wait renew
          assert(called); called = nil
          -- during call
          assert(called == nil)
          invalidate(conn.login.id)
          callwithin(conn, OfferRegistry.findServices, OfferRegistry, {})
          assert(called); called = nil
          -- during logout
          assert(called == nil)
          invalidate(conn.login.id)
          assert(conn:logout() == true)
          assert(called == nil)
          assertlogoff(conn)
          relogin()
        end
        
        do log:TEST "raise error"
          local raised = {"Oops!"}
          function conn:onInvalidLogin(login)
            assertCallback(self, login)
            error(raised)
          end
          -- during renew
          assert(called == nil)
          invalidate(conn.login.id)
          sleep(leasetime+2) -- wait renew
          assert(called); called = nil
          assertlogoff(conn)
          relogin()
          -- during call
          assert(called == nil)
          invalidate(conn.login.id)
          local ex = callwithin(conn, catcherr, OfferRegistry.findServices, OfferRegistry, {})
          assert(ex._repid == sysex.NO_PERMISSION)
          assert(ex.completed == "COMPLETED_NO")
          assert(ex.minor == idl.const.services.access_control.NoLoginCode)
          assert(called); called = nil
          assertlogoff(conn)
          relogin()
          -- during logout
          assert(called == nil)
          invalidate(conn.login.id)
          assert(conn:logout() == true)
          assert(called == nil)
          assertlogoff(conn)
        end
        
        log:TEST(false)
        
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
