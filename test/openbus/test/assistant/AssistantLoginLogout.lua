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
local socket = require "socket.core"
local Matcher = require "loop.debug.Matcher"
local Viewer = require "loop.debug.Viewer"
local table = require "loop.table"
local giop = require "oil.corba.giop"
local cothread = require "cothread"
local openbus = require "openbus"
local assistant = require "openbus.assistant"
local libidl = require "openbus.idl"
local idl = require "openbus.core.idl"
local msg = require "openbus.util.messages"
local log = require "openbus.util.logger"
local util = require "openbus.util.server"

require "openbus.test.util"

setorbcfg(...)

busref = assert(util.readfrom(busref, "r"))
syskey = assert(openbus.readKeyFile(syskey))

local smalltime = .1

local thread = coroutine.running()
local userdata = io.stdout
local sleep = cothread.delay

local sysex = giop.SystemExceptionIDs

local entity = nil -- defined later
local orb = openbus.initORB(orbcfg)
local OpenBusContext = orb.OpenBusContext
assert(OpenBusContext.orb == orb)
local conns = {}
local bus = orb:newproxy(busref, nil, "::scs::core::IComponent")

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
local function assertlogged(a)
  -- check constant attributes
  assert(a.orb == orb)
  -- check the failure of 'startSharedAuth'
  a:startSharedAuth():cancel()
  -- check the login is valid to perform calls
  local OfferRegistry = OpenBusContext:getOfferRegistry()
  assert(OfferRegistry ~= nil)
  assert(#(OfferRegistry:findServices{}) == 0)
  -- check assitant operations are working fine
  assert(#(a:findServices({}, 0)) == 0)  
  return a
end

local function assertlogoff(a)
  -- check constant attributes
  assert(a.orb == orb)
  -- check the failure of 'startSharedAuth'
  local ex = catcherr(a.startSharedAuth, a, 0)
  assert(ex._repid == sysex.NO_PERMISSION)
  assert(ex.completed == "COMPLETED_NO")
  assert(ex.minor == idl.const.services.access_control.NoLoginCode)
  -- check the login is invalid to perform calls
  local ex = catcherr(OpenBusContext.getOfferRegistry, OpenBusContext)
  assert(ex._repid == sysex.NO_PERMISSION)
  assert(ex.completed == "COMPLETED_NO")
  assert(ex.minor == idl.const.services.access_control.NoLoginCode)
  -- check assitant operations are working fine
  assert(#(a:findServices({}, 0)) == 0)  
  return a
end

log:TEST(true, "Illegal Connection Params")

do
  local InvalidParams = {
    bushost = {
      [true] = "bad field 'bushost' to 'create' %(expected nil|string, got boolean%)$",
      [false] = "bad field 'bushost' to 'create' %(expected nil|string, got boolean%)$",
      [123] = "bad field 'bushost' to 'create' %(expected nil|string, got number%)$",
      [{}] = "bad field 'bushost' to 'create' %(expected nil|string, got table%)$",
      [error] = "bad field 'bushost' to 'create' %(expected nil|string, got function%)$",
      [thread] = "bad field 'bushost' to 'create' %(expected nil|string, got thread%)$",
      [userdata] = "bad field 'bushost' to 'create' %(expected nil|string, got userdata%)$",
    },
    busport = {
      [true] = "bad field 'busport' to 'create' %(expected nil|number|string, got boolean%)$",
      [false] = "bad field 'busport' to 'create' %(expected nil|number|string, got boolean%)$",
      [{}] = "bad field 'busport' to 'create' %(expected nil|number|string, got table%)$",
      [error] = "bad field 'busport' to 'create' %(expected nil|number|string, got function%)$",
      [thread] = "bad field 'busport' to 'create' %(expected nil|number|string, got thread%)$",
      [userdata] = "bad field 'busport' to 'create' %(expected nil|number|string, got userdata%)$",
    },
    interval = {
      [-1] = "interval too small, minimum is 1 second",
      [0] = "interval too small, minimum is 1 second",
      [0.1] = "interval too small, minimum is 1 second",
      [0.9999] = "interval too small, minimum is 1 second",
    },
  }
  local ValidParams = {
    orb = orb,
    bushost = bushost,
    busport = busport,
    entity = user,
    password = password,
    domain = domain,
  }
  for name, values in pairs(InvalidParams) do
    for invalid, expected in pairs(values) do
      log:TEST("connect with invalid "..name.." = "..tostring(invalid))
      local params = table.copy(ValidParams)
      params[name] = invalid
      local ex = catcherr(assistant.create, params)
      assert(ex:match(expected))
    end
  end
end

log:TEST(false)

log:TEST(true, "Illegal Login Parameters")

local function assertLoginFailure(params, expected)
  local theAssistant
  local last, notified
  local observer = {
    onLoginFailure = function (self, anAssistant, ex)
      local now = socket.gettime()
      if type(expected) == "string" then
        assert(string.find(ex, expected, 1+#ex-#expected, true))
      else
        assert(Matcher{isomorphic=false,metatable=false}:match(expected, ex))
      end
      if last ~= nil then
        assert(now - last > 1)
        assert(anAssistant == theAssistant)
        anAssistant:shutdown()
        notified = true
      end
      last = now
    end
  }
  params.interval = 1
  params.observer = observer
  theAssistant = assistant.create(params)
  for i = 1, 3 do
    if notified then break end
    cothread.delay(theAssistant.interval)
  end
  assert(notified)
end

do
  local Field2Op = {
    password = "loginByPassword",
    privatekey = "loginByCertificate",
  }

  for _, invalid in ipairs{true,false,123,{},error,thread,userdata} do
    for field, secret in pairs{password=password, privatekey=syskey} do
      log:TEST("login by ",field," with invalid entity (",invalid,")")
      assertLoginFailure({
        orb = orb,
        busref = bus,
        entity = invalid,
        [field] = secret,
        domain = field=="password" and domain or nil,
      }, "bad argument #2 to '"..Field2Op[field].."' (expected string, got "..type(invalid)..")")
    end
  end

  for _, invalid in ipairs{true,false,123,{},error,thread,userdata} do
    log:TEST("login with invalid password (",invalid,")")
    assertLoginFailure({
      orb = orb,
      busref = bus,
      entity = user,
      password = invalid,
      domain = domain,
    }, "bad argument #3 to 'loginByPassword' (expected string, got "..type(invalid)..")")
  end

  for _, invalid in ipairs{true,false,123,"key",{},error,thread} do
    log:TEST("login with invalid private key (",invalid,")")
    assertLoginFailure({
      orb = orb,
      busref = bus,
      entity = user,
      privatekey = invalid,
    }, "bad argument #3 to 'loginByCertificate' (expected userdata, got "..type(invalid)..")")
  end

  log:TEST "login with wrong password"
  assertLoginFailure({
    orb = orb,
    busref = bus,
    entity = user,
    password = "WrongPassword",
    domain = domain,
  }, {_repid = assert(idl.types.services.access_control.AccessDenied)})

  log:TEST "login with entity without certificate"
  assertLoginFailure({
    orb = orb,
    busref = bus,
    entity = "NoCertif.",
    privatekey = syskey,
  }, {_repid = assert(idl.types.services.access_control.MissingCertificate)})

  log:TEST "login with wrong private key"
  assertLoginFailure({
    orb = orb,
    busref = bus,
    entity = system,
    privatekey = openbus.newKey(),
  }, {_repid = assert(idl.types.services.access_control.AccessDenied)})
end

log:TEST(false)

-- login as admin and provide additional functionality for the test
local invalidate, sharedauth, shutdown, leasetime do
  local orb = openbus.initORB(orbcfg)
  local OpenBusContext = orb.OpenBusContext
  local bus = orb:newproxy(busref, nil, "::scs::core::IComponent")
  local conn = OpenBusContext:connectByReference(bus)
  conn:loginByPassword(admin, admpsw, domain)
  OpenBusContext:setDefaultConnection(conn)
  leasetime = conn.AccessControl:renew()
  function invalidate(loginId)
    OpenBusContext:getLoginRegistry():invalidateLogin(loginId)
  end
  function sharedauth()
    return conn:startSharedAuth()
  end
  function shutdown()
    conn:logout()
    orb:shutdown()
  end
end

--local events = table.memoize(function () return 0 end)
--local observer = table.memoize(function (event)
--  return function (...)
--    events[event] = events[event] + 1
--  end
--end)

do
  local function testlogin(params)
    log:TEST("connect")
    local a = assistant.create(params)
    assert(#(a:findServices({}, -1)) == 0) -- wait until login
    assertlogged(a)
    log:TEST("renew login")
    sleep(2*leasetime)
    assertlogged(a)
    log:TEST "reconnect during renew"
    invalidate(OpenBusContext:getCurrentConnection().login.id)
    sleep(leasetime+2) -- wait renew
    assertlogged(a)
    log:TEST "reconnect during call"
    invalidate(OpenBusContext:getCurrentConnection().login.id)
    assertlogged(a)
    log:TEST "shutdown"
    a:shutdown()
    assertlogoff(a)
  end
  
  log:TEST(true, "login by password")
  testlogin{
    orb = orb,
    busref = bus,
    entity = user,
    password = password,
    domain = domain,
  }
  log:TEST(false)
  log:TEST(true, "login by private key")
  testlogin{
    orb = orb,
    busref = bus,
    entity = system,
    privatekey = syskey,
  }
  log:TEST(false)
  log:TEST(true, "login by shared authentication")
  testlogin{
    orb = orb,
    busref = bus,
    loginargs = function () return "SharedAuth", sharedauth() end,
  }
  log:TEST(false)
end

for interval = 1, 3 do
  log:TEST("access denied on relogin with interval of ",interval," seconds")
  local last, notified
  local entity, secret = user, password
  local a
  a = assistant.create{
    orb = orb,
    busref = bus,
    loginargs = function () return "Password", entity, secret, domain end,
    interval = interval,
    observer = {
      onLoginFailure = function (self, assist, except)
        local now = socket.gettime()
        assert(except._repid == idl.types.services.access_control.AccessDenied)
        if last ~= nil then
          assert(now - last > interval)
          assert(assist == a)
          assist:shutdown()
          notified = true
        end
        last = now
      end,
    },
  }
  assert(#(a:findServices{}) == 0) -- wait until login
  assertlogged(a)
  secret = "WrongPassword"
  invalidate(OpenBusContext:getCurrentConnection().login.id)
  assert(#(a:findServices{}) == 0) -- wait until relogin
  assert(notified)
end

orb:shutdown()
shutdown()
