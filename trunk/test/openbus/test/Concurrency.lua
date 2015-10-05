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
  function shutdown()
    conn:logout()
    orb:shutdown()
  end
end

local orb = openbus.initORB(orbcfg)
local OpenBusContext = orb.OpenBusContext
assert(OpenBusContext.orb == orb)
local busref = orb:newproxy(busref, nil, "::scs::core::IComponent")


do log:TEST("Two threads logging in")
  local conn = OpenBusContext:connectByReference(busref, connprops)
  local failures = 0
  local threads = 2
  local function trylogin()
    local ok, ex = pcall(conn.loginByPassword, conn, user, password, domain)
    threads = threads-1
    if not ok then
      failures = failures+1
      assert(ex._repid == libidl.types.AlreadyLoggedIn)
    end
  end
  
  for i = 1, threads do
    cothread.schedule(coroutine.create(trylogin))
  end
  repeat cothread.delay(smalltime) until threads == 0
  
  assert(conn.login ~= nil)
  assert(uuid.isvalid(conn.login.id))
  assert(conn.login.entity == user)
  assert(failures == 1)
  
  conn:logout()
end

do log:TEST("Two threads getting invalid login")
  local conn = OpenBusContext:connectByReference(busref, connprops)
  conn:loginByPassword(user, password, domain)
  OpenBusContext:setDefaultConnection(conn)
  local OfferRegistry = OpenBusContext:getOfferRegistry()
  
  local suspended = {}
  local mylogin = conn.login
  function conn:onInvalidLogin(login)
    assert(self == conn)
    assert(self.login == nil)
    assert(login == mylogin)
    suspended[#suspended+1] = cothread.running()
    cothread.suspend()
  end
  
  local failures = 0
  local threads = 2
  local function callop()
    local ok, ex = pcall(OfferRegistry.getAllServices, OfferRegistry)
    threads = threads-1
    if not ok then
      failures = failures+1
      assert(ex._repid == sysex.NO_PERMISSION)
      assert(ex.completed == "COMPLETED_NO")
      assert(ex.minor == idl.const.services.access_control.NoLoginCode)
    end
  end
  
  -- invalidate login
  invalidate(mylogin.id)
  
  -- perform calls with an invalid login
  for i = 1, threads do cothread.schedule(coroutine.create(callop)) end
  repeat cothread.delay(smalltime) until #suspended == threads
  
  -- check connection behavion while logged wiht invalid login
  assert(conn.login == nil)
  local ok, ex = pcall(conn.loginByPassword, conn, user, "ThisIsNot:"..password, domain)
  assert(not ok)
  assert(ex._repid == idl.types.services.access_control.AccessDenied)
  assert(conn.login == nil)
  
  for _, thread in ipairs(suspended) do cothread.schedule(thread) end
  repeat cothread.delay(smalltime) until threads == 0
  
  -- check connection after execution of callbacks
  assert(failures == 2)
  assert(conn.login == nil)
  
  OpenBusContext:setDefaultConnection(nil)
end

do log:TEST("Two threads getting invalid login while other relogs")
  local conn = OpenBusContext:connectByReference(busref, connprops)
  conn:loginByPassword(user, password, domain)
  OpenBusContext:setDefaultConnection(conn)
  local OfferRegistry = OpenBusContext:getOfferRegistry()
  
  local suspended = {}
  local mylogin = conn.login
  function conn:onInvalidLogin(login)
    assert(self == conn)
    assert(self.login == nil)
    assert(login == mylogin)
    suspended[#suspended+1] = cothread.running()
    cothread.suspend()
  end
  
  local failures = 0
  local threads = 2
  local function callop()
    OfferRegistry:getAllServices()
    threads = threads-1
  end
  
  -- invalidate login
  invalidate(mylogin.id)
  
  -- perform calls with an invalid login
  for i = 1, threads do cothread.schedule(coroutine.create(callop)) end
  repeat cothread.delay(smalltime) until #suspended == threads
  
  -- check connection behavion while logged wiht invalid login
  assert(conn.login == nil)
  conn:loginByPassword(user, password, domain)
  assert(conn.login ~= nil)
  assert(conn.login ~= mylogin)
  
  -- resume threads calling 'onInvalidLogin' callback
  for _, thread in ipairs(suspended) do cothread.schedule(thread) end
  repeat cothread.delay(smalltime) until threads == 0
  
  -- check connection after execution of callbacks
  assert(conn.login ~= nil)
  assert(conn.login ~= mylogin)
  
  conn:logout()
  OpenBusContext:setDefaultConnection(nil)
end

do log:TEST("Two threads getting invalid login and trying to relog")
  local conn = OpenBusContext:connectByReference(busref, connprops)
  conn:loginByPassword(user, password, domain)
  OpenBusContext:setDefaultConnection(conn)
  local OfferRegistry = OpenBusContext:getOfferRegistry()
  
  local suspended = {}
  local mylogin = conn.login
  local alreadylogged = 0
  function conn:onInvalidLogin(login)
    assert(self == conn)
    assert(self.login == nil)
    assert(login == mylogin)
    suspended[#suspended+1] = cothread.running()
    cothread.suspend()
    local ok, ex = pcall(conn.loginByPassword, conn, user, password, domain)
    if not ok then
      alreadylogged = alreadylogged+1
      assert(ex._repid == libidl.types.AlreadyLoggedIn)
    end
  end
  
  local failures = 0
  local threads = 2
  local function callop()
    local ok, ex = pcall(OfferRegistry.getAllServices, OfferRegistry)
    threads = threads-1
    if not ok then
      failures = failures+1
      assert(ex._repid == sysex.NO_PERMISSION)
      assert(ex.completed == "COMPLETED_NO")
      assert(ex.minor == idl.const.services.access_control.NoLoginCode)
    end
  end
  
  -- invalidate login
  invalidate(mylogin.id)
  
  -- perform calls with an invalid login
  for i = 1, threads do cothread.schedule(coroutine.create(callop)) end
  repeat cothread.delay(smalltime) until #suspended == threads
  
  -- check connection behavion while logged wiht invalid login
  assert(conn.login == nil)
  
  -- resume threads calling 'onInvalidLogin' callback
  for _, thread in ipairs(suspended) do cothread.schedule(thread) end
  repeat cothread.delay(smalltime) until threads == 0
  
  -- check connection after execution of callbacks
  assert(failures == 0)
  assert(alreadylogged == 1)
  assert(conn.login ~= nil)
  assert(conn.login ~= mylogin)
  
  conn:logout()
  OpenBusContext:setDefaultConnection(nil)
end

orb:shutdown()
shutdown()
