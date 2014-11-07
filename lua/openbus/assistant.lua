local _G = require "_G"
local assert = _G.assert
local error = _G.error
local ipairs = _G.ipairs
local pcall = _G.pcall

local math = require "math"
local max = math.max

local log = require "openbus.util.logger"
local msg = require "openbus.util.messages"

local oo = require "openbus.util.oo"
local class = oo.class

local libidl = require "openbus.idl"
local types = libidl.types

local openbus = require "openbus"
local sleep = openbus.sleep
local newthread = openbus.newThread

local assistant2 = require "openbus.assistant2"
local createConnection = assistant2.create



local function pause(interval)
  return sleep(max(1, interval))
end

local function callobserver(assistant, kind, ...)
  local observer = assistant.observer
  if observer ~= nil then
    local callback = observer["on"..kind.."Failure"]
    if callback ~= nil then
      local ok, errmsg = pcall(callback, observer, assistant, ...)
      if not ok then
        log:exception(msg.FailureOnFailureObserver:tag{errmsg=errmsg})
      end
    end
  end
end

local function doLogin(self)
  local conn = self.connection
  repeat
    local ok, result = pcall(conn.loginByCallback, conn, self.loginargs)
    if not ok then
      pause(callobserver(self, "Login", result) or conn.interval)
    end
  until ok or result._repid == types.AlreadyLoggedIn or self.canceled
end


local Observer = class()

function Observer:onLoginFailure(conn, except)
  return self.observer:onLoginFailure(conn.assistant, except)
end

function Observer:onLoginArgsFailure(conn, except)
  return self.observer:onLoginFailure(conn.assistant, except)
end

function Observer:onSetOfferPropsFailure(conn, except, offer, properties)
  return self.observer:onRegisterFailure(conn.assistant,
                                         offer.service_ref,
                                         properties,
                                         except)
end

function Observer:onOfferRegFailure(conn, except, context, service_ref, properties)
  return self.observer:onRegisterFailure(conn.assistant,
                                         service_ref,
                                         properties,
                                         except)
end

function Observer:onOfferRemovalFailure(conn, except, offer)
  return self.observer:onRemoveOfferFailure(conn.assistant,
                                            offer.service_ref,
                                            offer.properties,
                                            except)
end

--function Observer:onOfferRegObsSubsFailure(conn, except)
--  return ...
--end
--
--function Observer:onOfferRegObsRemovalFailure(conn, except)
--  return ...
--end
--
--function Observer:onOfferObsSubsFailure(conn, except)
--  return ...
--end
--
--function Observer:onOfferObsRemovalFailure(conn, except)
--  return ...
--end



local Assistant = class()

function Assistant:__init()
  local interval = self.interval
  if interval ~= nil then
    assert(interval >= 1, "interval too small, minimum is 1 second")
  end
  local password = self.password
  if self.password ~= nil then
    function self.loginargs()
      return "Password", self.entity, password
    end
    self.password = nil
  else
    local privatekey = self.privatekey
    if self.privatekey ~= nil then
      function self.loginargs()
        return "Certificate", self.entity, privatekey
      end
      self.privatekey = nil
    end
  end
  assert(self.loginargs ~= nil, "invalid login params callback")
  local conn = createConnection{
    interval = interval,
    orb = self.orb,
    bushost = self.bushost,
    busport = self.busport,
    accesskey = self.accesskey,
    nolegacy = self.nolegacy,
    legacydelegate = self.legacydelegate,
    observer = self.observer ~= nil and Observer{observer=self.observer} or nil,
  }
  if self.orb == nil then self.orb = conn.orb end
  local OpenBusContext = assert(self.orb.OpenBusContext, "invalid ORB")
  assert(OpenBusContext:getDefaultConnection() == nil, "ORB already in use")
  OpenBusContext:setDefaultConnection(conn.connection)
  self.offers = {}
  self.context = OpenBusContext
  self.connection = conn
  self.interval = conn.interval
  conn.assistant = self
  newthread(doLogin, self)
end

function Assistant:registerService(component, properties)
  self.connection:registerService(component, properties)
end

function Assistant:findServices(properties, retries, interval)
  if retries == nil then retries = -1 end
  local conn = self.connection
  local ok, result
  repeat
    ok, result = pcall(conn.findServices, conn, properties)
    if not ok then
      local newinterval = callobserver(self, "Find", result)
      if retries == 0 or self.canceled then
        return {}
      end
      retries = retries-1
      pause(interval or newinterval or conn.interval)
    end
  until ok
  return result
end

do
  local function retrycall(self, retries, interval, event, method, object, ...)
    if retries == nil then retries = -1 end
    local ok, result
    repeat
      ok, result = pcall(method, object, ...)
      if not ok then
        local newinterval = callobserver(self, event, ...)
        if retries == 0 or self.canceled then
          return error(result) -- TODO: is this the correct thing to do?
        end
        retries = retries-1
        pause(interval or newinterval or self.connection.interval)
      end
    until ok
    return result
  end

  function Assistant:startSharedAuth(retries, interval)
    local conn = self.connection
    return retrycall(self, retries, interval, "StartSharedAuth", conn.startSharedAuth, conn)
  end
end

function Assistant:shutdown()
  local OpenBusContext = self.orb.OpenBusContext
  self.connection:logout()
  if OpenBusContext:getDefaultConnection() == self.connection.connection then
    OpenBusContext:setDefaultConnection(nil)
  end
  self.canceled = true
end



local module = { create = Assistant }

function module.newSearchProps(entity, facet)
  return {
    {name="openbus.offer.entity",value=entity},
    {name="openbus.component.facet",value=facet},
  }
end

function module.getProperty(properties, name)
  for _, prop in ipairs(properties) do
    if prop.name == name then
      return prop.value
    end
  end
end

function module.activeOffers(offers)
  local active = {}
  for _, offer in ipairs(offers) do
    local service = offer.service_ref
    local ok, result = pcall(service._non_existent, service)
    if ok and not result then
      active[#active+1] = offer
    end
  end
  return active
end

return module
