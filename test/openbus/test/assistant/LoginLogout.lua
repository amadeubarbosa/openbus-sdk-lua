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
local ComponentContext = require "scs.core.ComponentContext"
local cothread = require "cothread"
local openbus = require "openbus"
local assistmod = require "openbus.assistant"
local libidl = require "openbus.idl"
local idl = require "openbus.core.idl"
local msg = require "openbus.util.messages"
local log = require "openbus.util.logger"

require "openbus.test.configs"

syskey = assert(openbus.readKeyFile(syskey))

local thread = coroutine.running()
local userdata = io.stdout
local sleep = cothread.delay

local sysex = giop.SystemExceptionIDs

local entity = nil -- defined later
local orb = openbus.initORB()
openbus.newThread(orb.run, orb)
local OpenBusContext = orb.OpenBusContext
local assistants = {}

local function catcherr(...)
  local ok, err = pcall(...)
  assert(not ok)
  return err
end

local loginways = {
  loginByPassword = function() return user, password end,
  loginByCertificate = function() return system, syskey end,
  loginByCallback = function()
    return function()
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
local function assertlogged(assistant)
  -- check constant attributes
  assert(assistant.orb == orb)
  -- check logged in only attributes
  assert(assistant.login ~= nil)
  assert(assistant.login.entity == entity)
  local loginid = assistant.login.id
  local busid = assistant.busid
  assert(uuid.isvalid(loginid))
  assert(uuid.isvalid(busid))
  -- check the attempt to login again
  for opname, getparams in pairs(loginways) do
    local ex = catcherr(assistant[opname], assistant, getparams())
    assert(ex._repid == libidl.types.AlreadyLoggedIn, ex)
    assert(assistant.login.entity == entity)
    assert(assistant.login.id == loginid)
    assert(assistant.busid == busid)
  end
  -- check the login is valid to perform calls
  assistant:findServices({})
  return assistant
end

local function assertlogoff(assistant)
  -- check constant attributes
  assert(assistant.orb == orb)
  -- check logged in only attributes
  assert(assistant.login == nil)
  assert(assistant.busid == nil)
  -- check the attempt to logoff again
  assert(assistant:logout() == false)
  -- check the failure of 'startSharedAuth'
  local ex = catcherr(assistant.startSharedAuth, assistant)
  assert(ex._repid == sysex.NO_PERMISSION)
  assert(ex.completed == "COMPLETED_NO")
  assert(ex.minor == idl.const.services.access_control.NoLoginCode)
  -- check the login is invalid to perform calls
  local ex = catcherr(assistant.findServices, assistant, {})
  assert(ex._repid == sysex.NO_PERMISSION)
  assert(ex.completed == "COMPLETED_NO")
  assert(ex.minor == idl.const.services.access_control.NoLoginCode)
  return assistant
end

log:TEST(true, "assistmod.create")

do log:TEST "assistant with invalid host"
  for _, invalid in ipairs{true,false,123,{},error,thread,userdata} do
    local ex = catcherr(assistmod.create, {bushost=invalid, busport=busport})
    assert(ex:match("bad field 'bushost' to 'create' %(expected string, got "..type(invalid).."%)$"))
  end
end

do log:TEST "assistant with invalid port"
  for _, invalid in ipairs{true,false,{},error,thread,userdata} do
    local ex = catcherr(assistmod.create, {bushost=bushost, busport=invalid})
    assert(ex:match("bad field 'busport' to 'create' %(expected number|string, got "..type(invalid).."%)$"))
  end
end

do log:TEST "connect to unavailable host"
  local assistant = assistmod.create{bushost="unavailable", busport=busport}
  for op, params in pairs(loginways) do
    local ex = catcherr(assistant[op], assistant, params())
    assert(ex._repid == sysex.TRANSIENT)
    assert(ex.completed == "COMPLETED_NO")
  end
end

do log:TEST "connect to unavailable port"
  local assistant = assistmod.create{bushost=bushost, busport=0}
  for op, params in pairs(loginways) do
    local ex = catcherr(assistant[op], assistant, params())
    assert(ex._repid == sysex.TRANSIENT)
    assert(ex.completed == "COMPLETED_NO")
  end
end

do log:TEST "connect to bus"
  for i = 1, 2 do
    assistants[i] = assertlogoff(assistmod.create{bushost=bushost, busport=busport, orb=orb})
  end
end

-- create a valid key to be used as a wrong key in the tests below.
-- the generation of this key is too time consuming and may delay the renewer
-- thread of the admin account to renew the admin login in time.
local WrongKey = openbus.newKey()
-- login as admin and provide additional functionality for the test
local invalidate, shutdown, leasetime do
  local OpenBusContext = openbus.initORB().OpenBusContext
  local conn = OpenBusContext:createConnection(bushost, busport)
  conn:loginByPassword(admin, admpsw)
  OpenBusContext:setDefaultConnection(conn)
  leasetime = conn.AccessControl:renew()
  function invalidate(loginId)
    OpenBusContext:getLoginRegistry():invalidateLogin(loginId)
  end
  function shutdown()
    conn:logout()
  end
end

for _, connOp in ipairs({"DefaultConnection", "CurrentConnection"}) do
  log:TEST(true, "assistant.loginBy* (",connOp,"=assistant[1])")
  
  do log:TEST "login with invalid entity"
    local assistant = assistants[1]
    for _, invalid in ipairs{nil,true,false,123,{},error,thread,userdata} do
      for _, op in ipairs{"loginByPassword", "loginByCertificate"} do
        local ex = catcherr(assistant[op], assistant, invalid, select(2, loginways[op]()))
        assert(ex:match("bad argument #1 to '"..op.."' %(expected string, got "..type(invalid).."%)$"))
        assertlogoff(assistant)
      end
    end
  end
  
  do log:TEST "login with invalid password"
    local assistant = assistants[1]
    for _, invalid in ipairs{nil,true,false,123,{},error,thread,userdata} do
      local ex = catcherr(assistant.loginByPassword, assistant, user, invalid)
      assert(ex:match("bad argument #2 to 'loginByPassword' %(expected string, got "..type(invalid).."%)$"))
      assertlogoff(assistant)
    end
  end
  
  do log:TEST "login with invalid private key"
    local assistant = assistants[1]
    for _, invalid in ipairs{nil,true,false,123,"key",{},error,thread} do
      local ex = catcherr(assistant.loginByCertificate, assistant, system, invalid)
      assert(ex:match("bad argument #2 to 'loginByCertificate' %(expected userdata, got "..type(invalid).."%)$"))
      assertlogoff(assistant)
    end
  end
  
  do log:TEST "login with wrong password"
    local assistant = assistants[1]
    local ex = catcherr(assistant.loginByPassword, assistant, user, "WrongPassword")
    assert(ex._repid == idl.types.services.access_control.AccessDenied)
    assertlogoff(assistant)
  end
  
  do log:TEST "login with entity without certificate"
    local assistant = assistants[1]
    local ex = catcherr(assistant.loginByCertificate, assistant, "NoCertif.", syskey)
    assert(ex._repid == idl.types.services.access_control.MissingCertificate)
    assert(ex.entity == "NoCertif.")
    assertlogoff(assistant)
  end
  
  do log:TEST "login with wrong private key"
    local assistant = assistants[1]
    local ex = catcherr(assistant.loginByCertificate, assistant, system, WrongKey)
    assert(ex._repid == idl.types.services.access_control.AccessDenied)
    assertlogoff(assistant)
  end
  
  do
    local autoprops = {
      "openbus.offer.id",
      "openbus.offer.login",
      "openbus.offer.entity",
      "openbus.offer.timestamp",
      "openbus.offer.year",
      "openbus.offer.month",
      "openbus.offer.day",
      "openbus.offer.hour",
      "openbus.offer.minute",
      "openbus.offer.second",
      "openbus.component.name",
      "openbus.component.version.major",
      "openbus.component.version.minor",
      "openbus.component.version.patch",
      --"openbus.component.facet",
      --"openbus.component.interface",
    }
    local function assertofferprops(expected, offer, registered)
      local properties = offer:describe().properties
      for _, property in ipairs(expected) do
        local actual = assistmod.getProperty(properties, property.name)
        assert(actual == property.value,
          "expected '"..tostring(property.value).."' but got "..tostring(actual).."'")
      end
      for _, propname in ipairs(autoprops) do
        if registered then
          assert(assistmod.getProperty(properties, propname) ~= nil)
        else
          assert(assistmod.getProperty(properties, propname) == nil)
        end
      end
    end

    local function testlogin(assistant, op, getparams)
      log:TEST("successful assistant.",op)
      -- create service SCS component
      local component = ComponentContext(orb, {
        name = "Test Component",
        major_version = 1,
        minor_version = 0,
        patch_version = 0,
        platform_spec = "Lua",
      })
      local offerspec = {
        component = component.IComponent,
        properties = {{name="custom.prop.name",value="Custom Property Value"}},
        altprops = {{name="alt.prop.name",value="Alternative Property Value"}},
      }
      if getparams == nil then getparams = loginways[op] end
      -- first login
      assistant[op](assistant, getparams())
      assertlogged(assistant)
      local loginid = assistant.login.id
      local busid = assistant.busid
      -- first logout
      assistant:logout()
      assertlogoff(assistant)
      -- second login
      assistant[op](assistant, getparams())
      local offer = assistant:registerService(offerspec.component,
                                              offerspec.properties)
      local function assertrelogged(justlogged)
        if justlogged then
          assertofferprops(offerspec.properties, offer)
          offer:setProperties(offerspec.altprops)
          assertofferprops(offerspec.altprops, offer)
          sleep(1)
          assertofferprops(offerspec.altprops, offer, "registered")
          offer:setProperties(offerspec.properties)
          assertofferprops(offerspec.altprops, offer, "registered")
          sleep(1)
        end
        assertofferprops(offerspec.properties, offer, "registered")
        assertlogged(assistant)
        assert(assistant.login.id ~= loginid)
        assert(assistant.busid == busid)
        loginid = assistant.login.id
      end
      assertrelogged("justlogged")
      -- automatic login renew
      sleep(2*leasetime)
      assertlogged(assistant)
      assert(assistant.login.id == loginid)
      assert(assistant.busid == busid)
      
      for otherIdx, other in ipairs(assistants) do
        if other.login == nil then
          
          log:TEST(true, "assistant.loginByCallback (from=assistant.",op,")")
          
          do log:TEST "login with wrong secret"
            local attempt = assistant:startSharedAuth()
            local ex = catcherr(other.loginByCallback, other,
              function () return "SharedAuth", attempt, "WrongSecret" end)
            assert(ex._repid == idl.types.services.access_control.AccessDenied)
            assertlogoff(other)
            assertlogged(assistant)
          end
          do log:TEST "login with canceled attempt"
            local attempt, secret = assistant:startSharedAuth()
            assistant:cancelSharedAuth(attempt)
            local ex = catcherr(other.loginByCallback, other,
              function () return "SharedAuth", attempt, secret end)
            assert(ex._repid == libidl.types.InvalidLoginProcess)
            assertlogoff(other)
            assertlogged(assistant)
          end
          do log:TEST "login with expired attempt"
            local attempt, secret = assistant:startSharedAuth()
            sleep(2*leasetime)
            local ex = catcherr(other.loginByCallback, other,
              function () return "SharedAuth", attempt, secret end)
            assert(ex._repid == libidl.types.InvalidLoginProcess)
            assertlogoff(other)
            assertlogged(assistant)
          end
          do
            testlogin(other, "loginByCallback", function()
              return function ()
                return "SharedAuth", assistant:startSharedAuth()
              end
            end)
            assertlogged(assistant)
          end
          
          log:TEST(false)
          
          break
        end
      end
      
      do log:TEST "become invalid"
        -- during renew
        invalidate(loginid)
        sleep(leasetime+2) -- wait renew
        assertrelogged()
        -- during call
        invalidate(loginid)
        assistant:findServices({})
        assertrelogged()
      end
      
      -- last logout
      assistant:logout()
      assertlogoff(assistant)
    end
    
    entity = user; testlogin(assistants[1], "loginByPassword")
    entity = system; testlogin(assistants[1], "loginByCertificate")
  end
  
  log:TEST(false)
end

log:TEST(false)

shutdown()
orb:shutdown()
