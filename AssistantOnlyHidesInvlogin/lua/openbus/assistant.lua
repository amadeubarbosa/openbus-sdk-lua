local _G = require "_G"
local assert = _G.assert
local error = _G.error
local ipairs = _G.ipairs
local next = _G.next
local pairs = _G.pairs
local pcall = _G.pcall

local coroutine = require "coroutine"
local running = coroutine.running

local cothread = require "cothread"
cothread.plugin(require "cothread.plugin.sleep")
cothread.plugin(require "cothread.plugin.signal")
local resume = cothread.next
local notify = cothread.notify
local schedule = cothread.schedule
local suspend = cothread.suspend
local wait = cothread.wait

local vararg = require "vararg"
local packargs = vararg.pack

local Wrapper = require "loop.object.Wrapper"

local giop = require "oil.corba.giop"
local sysexid = giop.SystemExceptionIDs

local log = require "openbus.util.logger"
local msg = require "openbus.util.messages"
local oo = require "openbus.util.oo"
local class = oo.class
local sysex = require "openbus.util.sysex"

local coreidl = require "openbus.core.idl"
local const = coreidl.const.services.access_control

local libidl = require "openbus.idl"
local throw = libidl.throw
local types = libidl.types

local openbus = require "openbus"
local sleep = openbus.sleep
local newthread = openbus.newThread
local initORB = openbus.initORB

-- must be loaded after OiL is loaded because OiL is the one that installs
-- the cothread plug-in that supports these operations.


local function callobserver(assistant, kind, ...)
  log:exception(msg.OperationFailure:tag{kind=kind, errmsg=...})
  local observer = assistant.observer
  if observer ~= nil then
    local callback = observer["on"..kind.."Failure"]
    if callback ~= nil then
      if not pcall(callback, observer, assistant, ...) then
        log:exception(msg.FailureOnFailureObserver:tag{
          errmsg=assistant.interval,
        })
      end
    end
  end
end

local function tcall_cont(assistant, kind, func, args, ok, ...)
  if ok then
    log:action(false, msg.InsistentCallFinished:tag{category=kind})
    return ...
  end
  callobserver(assistant, kind, ...)
  log:action(msg.InsistentCallAttemptFailed:tag{category=kind,interval=assistant.interval})
  sleep(assistant.interval)
  return tcall_cont(assistant, kind, func, args, pcall(func, args()))
end

local function tcall(assistant, kind, func, ...)
  log:action(true, msg.InsistentCallStarted:tag{category=kind})
  return tcall_cont(assistant, kind, func, packargs(...), pcall(func, ...))
end

local function subscribeRegObs(context, observer, properties)
  return context:getOfferRegistry():subscribeObserver(observer, properties)
end

local function subscribeOffObs(observer, offer)
  return offer:subscribeObserver(observer)
end

local function newoffer(context, component, properties)
  local offer = context:getOfferRegistry():registerService(component,properties)
  return offer:describe()
end

local function loginConnection(conn, loginWay, ...)
  log:action(msg.LoginAttempt:tag{mode=loginWay})
  return pcall(conn["loginBy"..loginWay], conn, ...)
end

local function loginAssistant(assistant)
  local conn = assistant.connection
  local ok, result = loginConnection(conn,
    tcall(assistant, "LoginArgs", assistant.loginargs, assistant))
  if ok then
    assistant.login = conn.login
    assistant.busid = conn.busid
    for task in pairs(assistant.tasks) do
      task:send(true)
    end
  end
  return ok, result
end

local function onInvalidLogin(conn)
  local assistant = conn.assistant
  while assistant.logouttask == nil do
    local ok, result = loginAssistant(assistant)
    if ok or result._repid == types.AlreadyLoggedIn then
      break
    end
    callobserver(assistant, "Login", result)
  end
end


local BackgroundTask = class()

function BackgroundTask:__init()
  newthread(function ()
    local assistant = self.assistant
    assistant.context:setCurrentConnection(assistant.connection)
    local thread = running()
    repeat
      local event = self.event
      while event == nil do
        self.thread = thread   -- registers it is waiting for an event
        suspend()              -- wait the event
        event = self.event
      end
      self.event = nil         -- consume the event and continue
      self:receive(event)
    until false
  end)
end

function BackgroundTask:send(event)
  self.event = event    -- register event to be processed later
  local thread = self.thread
  if thread ~= nil then -- there is a thread waiting for the event
    self.thread = nil   -- clear the thread waiting
    schedule(thread)    -- wake thread waiting
  end
end


local LoginTriggeredTask = oo.class({}, BackgroundTask)

function LoginTriggeredTask:__init()
  self.description = self
  self.ref = self
  local assistant = self.assistant
  assistant.tasks[self] = true
  if assistant.connection.login ~= nil and assistant.logouttask == nil then
    self:send(true)
  end
end

function LoginTriggeredTask:terminate()
  local assistant = self.assistant
  local tasks = assistant.tasks
  local logouttask = assistant.logouttask
  tasks[self] = nil
  if next(tasks) == nil and logouttask ~= nil then
    log:action(msg.NotifyTasksConclusion)
    assistant.logouttask = nil
    schedule(logouttask)
  end
end

function LoginTriggeredTask:invalid()
  local conn = self.assistant.connection
  return conn.login ~= nil and conn.login.id ~= self.login
end

function LoginTriggeredTask:describe()
  if not self:invalid() then
    self.description = self.description.ref:describe()
  end
  return self.description
end

function LoginTriggeredTask:remove()
  self:send(false)
end


local OfferRegistryObserverSubscription = class({}, LoginTriggeredTask)

function OfferRegistryObserverSubscription:receive(keepSubscription)
  local assistant = self.assistant
  if keepSubscription then
    while self:invalid() do
      log:action(msg.SubscribeServiceOfferObserver)
      local description = tcall(assistant, "OfferRegObsSubs", subscribeRegObs,
                                                              assistant.context,
                                                              self.observer,
                                                              self.properties)
      local login = assistant.connection.login
      self.login = login and login.id
      self.description = description
    end
  else
    log:action(msg.UnsubscribeServiceOfferObserver)
    local subscription = self.description.ref
    tcall(assistant, "OfferRegObsRemoval", subscription.remove, subscription)
    self.description = self
    self.login = nil
    self:terminate()
  end
end


local OfferObserverSubscription = class({}, LoginTriggeredTask)

function OfferObserverSubscription:receive(keepSubscription)
  local assistant = self.assistant
  if keepSubscription then
    while self:invalid() do
      log:action(msg.SubscribeOfferRegistryObserver)
      local description = tcall(assistant, "OfferObsSubs", subscribeOffObs,
                                                           self.observer,
                                                           self.offer)
      local login = assistant.connection.login
      self.login = login and login.id
      self.description = description
    end
  else
    log:action(msg.UnsubscribeOfferRegistryObserver)
    local subscription = self.description.ref
    tcall(assistant, "OfferObsRemoval", subscription.remove, subscription)
    self.description = self
    self.login = nil
    self:terminate()
  end
end


local SetPropTask = class({}, BackgroundTask)

function SetPropTask:receive()
  local offer = self.offer
  while not offer:invalid() do
    log:action(msg.SetServiceOfferProperties)
    local ref = offer.description.ref
    local properties = offer.properties
    local ok, result = pcall(ref.setProperties, ref, properties)
    if ok or result._repid == sysexid.OBJECT_NOT_EXIST then
      offer.description.properties = properties
      break
    end
    callobserver(self, "SetOfferProps", result)
  end
end


local RegisteredOffer = class({}, LoginTriggeredTask)

function RegisteredOffer:__init()
  self.setPropTask = SetPropTask{ assistant = self.assistant, offer = self }
  self.description = self
  self.ref = self
end

function RegisteredOffer:receive(keepOffer)
  local assistant = self.assistant
  if keepOffer then
    while self:invalid() do
      log:action(msg.RegisterServiceOffer)
      local proptask = self.setPropTask
      local properties = self.properties
      local description = tcall(assistant, "OfferReg", newoffer,
                                                       assistant.context,
                                                       self.service_ref,
                                                       properties)
      properties = description.properties
      for _, property in ipairs(properties) do
        if property.name == "openbus.offer.login" then
          self.login = property.value
        end
      end
      self.description = description
      if properties ~= self.properties then
        proptask:send(true)
      end
    end
  else
    log:action(msg.RemoveServiceOffer)
    local offer = self.description.ref
    tcall(assistant, "OfferRemoval", offer.remove, offer)
    self.description = self
    self.login = nil
    self:terminate()
  end
end

function RegisteredOffer:setProperties(properties)
  self.properties = properties
  self.setPropTask:send(true)
end

function RegisteredOffer:subscribeObserver(observer, properties)
  local assistant = self.assistant
  if assistant.loginargs == nil then
    sysex.NO_PERMISSION{ minor = const.NoLogin }
  end
  return OfferObserverSubscription{
    assistant = assistant,
    offer = self,
    observer = observer,
    properties = properties,
  }
end


local Assistant = class{ interval = 3 }

function Assistant:__init()
  if self.orb == nil then self.orb = initORB() end
  local OpenBusContext = assert(self.orb.OpenBusContext, "invalid ORB")
  local conn = OpenBusContext:createConnection(self.bushost, self.busport, self)
  if OpenBusContext:getDefaultConnection() == nil then
    OpenBusContext:setDefaultConnection(conn)
  end
  self.tasks = {}
  self.context = OpenBusContext
  self.connection = conn
  conn.assistant = self
  conn.onInvalidLogin = onInvalidLogin
end

do
  local function localLogin(assistant)
    local ok, result = loginAssistant(assistant)
    if not ok then
      assistant:logout()
      error(result)
    end
  end

  function Assistant:loginByPassword(entity, password)
    if self.loginargs ~= nil then throw.AlreadyLoggedIn() end
    function self.loginargs() return "Password", entity, password end
    localLogin(self)
  end

  function Assistant:loginByCertificate(entity, key)
    if self.loginargs ~= nil then throw.AlreadyLoggedIn() end
    function self.loginargs() return "Certificate", entity, key end
    localLogin(self)
  end

  function Assistant:loginByCallback(callback)
    if self.loginargs ~= nil then throw.AlreadyLoggedIn() end
    self.loginargs = callback
    localLogin(self)
  end
end

for _, name in ipairs{"startSharedAuth", "cancelSharedAuth"} do
  Assistant[name] = function (self, ...)
    local conn = self.connection
    return conn[name](conn, ...)
  end
end

do
  local function wrapOffers(assistant, offers)
    for _, desc in ipairs(offers) do
      desc.ref = Wrapper{
        __object = desc.ref,
        assistant = self,
        description = desc,
        describe = RegisteredOffer.describe,
        subscribeObserver = RegisteredOffer.subscribeObserver,
      }
    end
    return offers
  end

  local function callOfferReg(context, opname, ...)
    local offers = context:getOfferRegistry()
    return offers[opname](offers, ...)
  end

  for _, name in ipairs{"findServices", "getAllServices"} do
    Assistant[name] = function (self, ...)
      local context = self.context
      local conn = context:setCurrentConnection(self.connection)
      local ok, result = pcall(callOfferReg, context, name, ...)
      context:setCurrentConnection(conn)
      if not ok then error(result) end
      return wrapOffers(self, result)
    end
  end
end

function Assistant:registerService(component, properties)
  if self.loginargs == nil then
    sysex.NO_PERMISSION{ minor = const.NoLogin }
  end
  return RegisteredOffer{
    assistant = self,
    service_ref = component,
    properties = properties,
  }
end

function Assistant:subscribeObserver(observer, properties)
  if self.loginargs == nil then
    sysex.NO_PERMISSION{ minor = const.NoLogin }
  end
  return OfferRegistryObserverSubscription{
    assistant = self,
    observer = observer,
    properties = properties,
  }
end

function Assistant:logout()
  if self.loginargs ~= nil then
    local task = self.logouttask
    if task == nil then             -- no one is performing a logout
      log:request(msg.LogoutProcessInitiated)
      task = running()
      self.logouttask = task        -- indicate is waiting tasks termination
      local tasks = self.tasks
      if next(tasks) ~= nil then    -- there are active tasks
        for task in pairs(tasks) do -- for all active tasks
          task:send(false)          -- send event asking task to terminate
        end
        log:request(msg.WaitingTasksConclusion)
        suspend()                   -- wait until all tasks terminate
        log:request(msg.BackgroundTasksConcluded)
      end
      local result = self.connection:logout()
      self.login = nil              -- forget about the last valid login
      self.busid = nil              -- forget about the last valid busid
      self.loginargs = nil          -- indicate assistant is no longer logged
      self.logouttask = nil         -- indicate logout terminated
      log:request(msg.LogoutProcessConcluded)
      notify(task)                  -- notify logout process concluded
      return result
    else                            -- some other thread is performing a logout
      log:request(msg.WaitingForLogoutProcessToBeConcluded)
      wait(task)                    -- wait for logout termination
      log:request(msg.LogoutProcessConclusionNotificationReceived)
    end
  end
  return false
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


-- insert function argument typing
local argcheck = require "openbus.util.argcheck"
argcheck.convertclass(Assistant, {
  loginByPassword = { "string", "string" },
  loginByCertificate = { "string", "userdata" },
  loginByCallback = { "function" },
  startSharedAuth = {},
  cancelSharedAuth = { "table" },
  logout = {},
  getAllServices = {},
  findServices = { "table" },
  registerService = { "table|userdata", "table" },
  subscribeObserver = { "table|userdata", "table" },
})
argcheck.convertmodule(module, {
  create = {
    bushost = "string",
    busport = "number|string",
  },
  newSearchProps = { "string", "string" },
  getProperty = { "table", "string" },
  activeOffers = { "table" },
})


return module
