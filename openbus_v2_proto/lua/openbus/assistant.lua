local vararg = require "vararg"
local packargs = vararg.pack

local log = require "openbus.util.logger"
local msg = require "openbus.util.messages"

local oo = require "openbus.util.oo"
local class = oo.class

local libidl = require "openbus.idl"
local types = libidl.types

local openbus = require "openbus"
local sleep = openbus.sleep
local newthread = openbus.newThread
local initORB = openbus.initORB



local function callobserver(assistant, kind, ...)
  local observer = assistant.observer
  if observer ~= nil then
    local callback = observer["on"..kind.."Failure"]
    if callback ~= nil then
      local ok, interval = pcall(callback, observer, assistant, ...)
      if ok then
        return interval
      end
      log:exception(msg.FailureOnFailureObserver:tag{errmsg=interval})
    end
  end
end

local function tcall_cont(assistant, kind, func, args, ok, ...)
  if ok then return ... end
  sleep(callobserver(assistant, kind, ...) or assistant.interval)
  return tcall_cont(assistant, kind, func, args, pcall(func, args()))
end

local function tcall(assistant, kind, func, ...)
  return tcall_cont(assistant, kind, func, packargs(...), pcall(func, ...))
end

local function newoffer(context, component, properties)
  return context:getOfferRegistry():registerService(component, properties)
end

local function getoffers(context, properties)
  return context:getOfferRegistry():findServices(properties)
end


local Offerrer = class()

function Offerrer:reset()
  self.offer = nil
end

function Offerrer:cancel()
  local offer = self.offer
  if offer then
    self.offer = false
    tcall(self.assistant, "Offer", offer.remove, offer)
  end
  self.offer = false
end

function Offerrer:activate()
  if self.offer == nil and self.active == nil then
    openbus.newThread(function ()
      self.active = true
      local assistant = self.assistant
      local offer = tcall(assistant, "Offer", newoffer, assistant.context,
                                                        self.component,
                                                        self.properties)
      if self.offer == nil then
        self.offer = offer
      elseif self.offer == false then
        tcall(assistant, "Offer", offer.remove, offer)
      end
      self.active = nil
    end)
  end
end


local function reloginOnInvalidLogin(assistant, conn, loginWay, ...)
  local loginop = conn["loginBy"..loginWay]
  repeat
    local ok, result = pcall(loginop, conn, ...)
  until ok or result._repid == types.AlreadyLoggedIn
  if assistant.canceled then
    conn:logout()
  else
    for _, offerrer in pairs(assistant.offers) do
      offerrer:activate()
    end
  end
end

local function handleOnInvalidLogin(conn)
  local assistant = conn.assistant
  for _, offerrer in pairs(assistant.offers) do
    offerrer:reset()
  end
  return reloginOnInvalidLogin(assistant, conn,
    tcall(assistant, "Login", assistant.loginargs, assistant))
end


local Assistant = class{ interval = 3 }

function Assistant:__init()
  if self.orb == nil then self.orb = initORB() end
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
  local OpenBusContext = assert(self.orb.OpenBusContext, "invalid ORB")
  local conn = OpenBusContext:createConnection(self.bushost, self.busport, self)
  assert(OpenBusContext:getDefaultConnection() == nil, "ORB already in use")
  OpenBusContext:setDefaultConnection(conn)
  self.offers = {}
  self.context = OpenBusContext
  self.connection = conn
  conn.assistant = self
  conn.onInvalidLogin = handleOnInvalidLogin
  newthread(handleOnInvalidLogin, conn)
end

function Assistant:registerService(component, properties)
  local offerrer = Offerrer{
    assistant = self,
    component = component,
    properties = properties,
  }
  self.offers[component] = offerrer
  if self.connection.login ~= nil then
    offerrer:activate()
  end
end

function Assistant:unregisterService(component)
  local offerrer = self.offers[component]
  if offerrer ~= nil then
    offerrer:cancel()
    return offerrer.properties
  end
end

function Assistant:findServices(properties, retries, interval)
  if retries == nil then retries = -1 end
  local ok, result
  repeat
    ok, result = pcall(getoffers, self.context, properties)
    if not ok then
      local newinterval = callobserver(self, "Find", result)
      if retries == 0 then
        return {}
      end
      retries = retries-1
      sleep(newinterval or interval or self.interval)
    end
  until ok
  return result
end

function Assistant:shutdown()
  self.canceled = true
  for _, offerrer in pairs(self.offers) do
    offerrer:cancel()
  end
  self.connection:logout()
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
