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

bushost, busport, verbose = ...
require "openbus.test.configs"

--cothread.verbose:flag("threads", true)
--cothread.verbose:flag("state", true)

local smalltime = .1
local accesskey = openbus.newKey()

-- login as admin and provide additional functionality for the test
local invalidate, shutdown do
  local orb = openbus.initORB()
  local OpenBusContext = orb.OpenBusContext
  local conn = OpenBusContext:createConnection(bushost, busport)
  conn:loginByPassword(admin, admpsw)
  OpenBusContext:setDefaultConnection(conn)
  function invalidate(loginId)
    OpenBusContext:getLoginRegistry():invalidateLogin(loginId)
  end
  function shutdown()
    conn:logout()
    orb:shutdown()
  end
end

local orb = openbus.initORB()
local OpenBusContext = orb.OpenBusContext
assert(OpenBusContext.orb == orb)


do log:TEST("Two threads logging in")
  local conn = assistant.create{
    orb = orb,
    bushost = bushost,
    busport = busport,
    accesskey = accesskey,
  }
  local failures = 0
  local threads = 2
  local function trylogin()
    local ok, ex = pcall(conn.loginByPassword, conn, user, password)
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
  
  assert(conn:logout() == true)
end

do log:TEST("Two threads getting invalid login and trying to relog")
  local conn = assistant.create{
    orb = orb,
    bushost = bushost,
    busport = busport,
    accesskey = accesskey,
  }
  conn:loginByPassword(user, password)
  OpenBusContext:setDefaultConnection(conn.connection)
  
  local mylogin = conn.login
  
  local failures = 0
  local threads = 2
  local function callop()
    conn:getAllServices()
    threads = threads-1
  end
  
  -- invalidate login
  invalidate(mylogin.id)
  
  -- perform calls with an invalid login
  for i = 1, threads do cothread.schedule(coroutine.create(callop)) end
  repeat cothread.delay(smalltime) until threads == 0
  
  -- check connection after execution of callbacks
  assert(conn.login ~= nil)
  assert(conn.login ~= mylogin)
  
  conn:logout()
  OpenBusContext:setDefaultConnection(nil)
end

orb:shutdown()
shutdown()