local _G = require "_G"
local assert = _G.assert
local error = _G.error
local ipairs = _G.ipairs
local next = _G.next
local pairs = _G.pairs
local pcall = _G.pcall
local rawget = _G.rawget
local setmetatable = _G.setmetatable
local tostring = _G.tostring

local coroutine = require "coroutine"
local newthread = coroutine.create

local math = require "math"
local inf = math.huge

local hash = require "lce.hash"
local sha256 = hash.sha256

local pubkey = require "lce.pubkey"
local decodepubkey = pubkey.decodepublic

local table = require "loop.table"
local copy = table.copy
local memoize = table.memoize

local LRUCache = require "loop.collection.LRUCache"
local Wrapper = require "loop.object.Wrapper"

local cothread = require "cothread"
local resume = cothread.next
local running = cothread.running
local threadtrap = cothread.trap
local unschedule = cothread.unschedule

local Mutex = require "cothread.Mutex"

local giop = require "oil.corba.giop"
local sysex = giop.SystemExceptionIDs

local log = require "openbus.util.logger"
local msg = require "openbus.util.messages"
local oo = require "openbus.util.oo"
local class = oo.class
local sysexthrow = require "openbus.util.sysex"

local idl = require "openbus.core.idl"
local BusLogin = idl.const.BusLogin
local ServiceFailure = idl.throw.services.ServiceFailure
local loginthrow = idl.throw.services.access_control
local loginconst = idl.const.services.access_control
local logintypes = idl.types.services.access_control
local offerconst = idl.const.services.offer_registry
local offertypes = idl.types.services.offer_registry
local BusObjectKey = idl.const.BusObjectKey
local access = require "openbus.core.Access"
local neworb = access.initORB
local setNoPermSysEx = access.setNoPermSysEx
local CoreInterceptor = access.Interceptor
local sendBusRequest = CoreInterceptor.sendrequest
local receiveBusReply = CoreInterceptor.receivereply
local receiveBusRequest = CoreInterceptor.receiverequest

-- must be loaded after OiL is loaded because OiL is the one that installs
-- the cothread plug-in that supports the 'now' operation.
local delay = cothread.delay
local time = cothread.now



local function getEntryFromCache(self, loginId)
  local logins = self.__object
  local ids = self.ids
  local validity = self.validity
  local timeupdated = self.timeupdated
  -- use information in the cache to validate the login
  local entry = self.logininfo:get(loginId)
  local time2live = validity[entry.index]
  if time2live == 0 then
    log:LOGIN_CACHE(msg.InvalidLoginInValidityCache:tag{
      login = loginId,
      entity = entry.entity,
    })
  elseif time2live ~= nil and time2live > time()-timeupdated then
    log:LOGIN_CACHE(msg.ValidLoginInValidityCache:tag{
      login = loginId,
      entity = entry.entity,
    })
    return entry -- valid login in cache
  else -- update validity cache
    log:LOGIN_CACHE(msg.UpdateLoginValidityCache:tag{count=#ids})
    self.timeupdated = time()
    validity = logins:getValidity(ids)
    self.validity = validity
    if validity[entry.index] > 0 then
      return entry -- valid login
    end
  end
end


local function getLoginEntry(self, loginId)
  local mutex = self.mutex
  repeat until mutex:try() -- get exclusive access to this cache
  local ok, entity = pcall(getEntryFromCache, self, loginId)
  mutex:free() -- release exclusive access so other threads can access
  if not ok then error(entity) end
  return entity
end

local function getLoginInfo(self, loginId)
  local login = self:getLoginEntry(loginId)
  if login ~= nil then
    return login
  end
  loginthrow.InvalidLogins{loginIds={loginId}}
end

local function newLoginRegistryWrapper(logins)
  local ids = {}
  local validity = {}
  local logininfo = LRUCache()
  local self = Wrapper{
    __object = logins,
    ids = ids,
    validity = validity,
    logininfo = logininfo,
    timeupdated = -inf,
    mutex = Mutex(),
    getLoginEntry = getLoginEntry,
    getLoginInfo = getLoginInfo,
  }
  function logininfo.retrieve(loginId, replacedId, entry)
    local index
    if entry == nil then
      index = #ids+1
      entry = { index = index }
    else
      index = entry.index
    end
    local ok, info, enckey = pcall(logins.getLoginInfo, logins, loginId)
    if ok then
      local pubkey, exception = decodepubkey(enckey)
      if pubkey == nil then
        logininfo:remove(loginId)
        error(exception)
      end
      entry.entity = info.entity
      entry.encodedkey = enckey
      entry.pubkey = pubkey
      validity[index] = time()-self.timeupdated -- valid until this moment
    elseif info._repid == logintypes.InvalidLogins then
      entry.entity = nil
      entry.encodedkey = nil
      entry.pubkey = nil
      validity[index] = 0
    else
      logininfo:remove(loginId)
      error(info)
    end
    entry.id = loginId
    ids[index] = loginId
    return entry
  end
  return self
end

local function unmarshalChain(self, signed)
  local decoder = self.orb:newdecoder(signed.encoded)
  return decoder:get(self.types.CallChain)
end

local function unmarshalBusId(self, contexts)
  local decoder = self.orb:newdecoder(contexts[CredentialContextId])
  return decoder:get(self.types.Identifier)
end

local function getBusId(self, contexts)
  local ok, result = pcall(unmarshalBusId, self, contexts)
  if ok then return result end
end

local pcallWithin do
  local function continuation(manager, backup, ...)
    manager:setRequester(backup)
    return ...
  end
  function pcallWithin(self, obj, op, ...)
    local manager = self.manager
    local backup = manager:getRequester()
    manager:setRequester(self)
    return continuation(manager, backup, pcall(obj[op], obj, ...))
  end
end

local callWithin do
  local function continuation(ok, errmsg, ...)
    if not ok then error(errmsg, 3) end
    return errmsg, ...
  end
  function callWithin(...)
    return continuation(pcallWithin(...))
  end
end

local function newRenewer(self, lease)
  local thread
  thread = newthread(function()
    local login = self.login
    local access = self.AccessControl
    while self.login == login do
      self.renewer = thread
      delay(lease)
      self.renewer = nil
      log:action(msg.RenewLogin:tag{id=login.id,entity=login.entity})
      local ok, result = pcall(access.renew, access)
      if ok then
        lease = result
      else
        log:exception(msg.FailedToRenewLogin:tag{error = result})
      end
    end
  end)
  self.manager.requesterOf[thread] = self
  resume(thread)
end

local function localLogout(self)
  self.login = nil
  self:resetCaches()
  local renewer = self.renewer
  if renewer ~= nil then
    self.renewer = nil
    unschedule(renewer)
  end
end

local function localLogin(self, busid, login, lease)
  if self.busid ~= busid then error(msg.InvalidBus) end
  if self.login ~= nil then error(msg.AlreadyLoggedIn) end
  self.invalidLogin = nil
  self.login = login
  newRenewer(self, lease)
end

local function getLogin(self)
  local login = self.login
  if login == nil then
    -- try to recover from an invalid login
    local invlogin = self.invalidLogin
    while invlogin ~= nil do
      self:onInvalidLogin(invlogin)
      local current = self.invalidLogin
      if current == invlogin then
        self.invalidLogin = nil
        invlogin = nil
      else
        invlogin = current
      end
    end
    login = self.login
  end
  return login
end

local LoginServiceNames = {
  AccessControl = "AccessControl",
  certificates = "CertificateRegistry",
  logins = "LoginRegistry",
}
local OfferServiceNames = {
  interfaces = "InterfaceRegistry",
  entities = "EntityRegistry",
  offers = "OfferRegistry",
}



local Connection = class({}, CoreInterceptor)

function Connection:__init()
  local orb = self.orb
  -- retrieve IDL definitions for login
  self.types.Identifier =
    assert(orb.types:lookup_id(idl.types.Identifier))
  self.types.LoginAuthenticationInfo =
    assert(orb.types:lookup_id(logintypes.LoginAuthenticationInfo))
  -- retrieve core service references
  local bus = self.bus
  for field, name in pairs(LoginServiceNames) do
    local facetname = assert(loginconst[name.."Facet"], name)
    local typerepid = assert(logintypes[name], name)
    local facet = assert(bus:getFacetByName(facetname), name)
    self[field] = orb:narrow(facet, typerepid)
  end
  for field, name in pairs(OfferServiceNames) do
    local facetname = assert(offerconst[name.."Facet"], name)
    local typerepid = assert(offertypes[name], name)
    local facet = assert(bus:getFacetByName(facetname), name)
    self[field] = orb:narrow(facet, typerepid)
  end
  -- create wrapper for core service LoginRegistry
  self.logins = newLoginRegistryWrapper(self.logins)
  local access = self.AccessControl
  self.busid = access:_get_busid()
  self.buskey = assert(decodepubkey(access:_get_buskey()))
  
  local legacy = self.legacy
  if legacy ~= nil then
    local facet = assert(legacy:getFacetByName("IAccessControlService_v1_05"))
    local oldidl = require "openbus.core.legacy.idl"
    local oldtypes = oldidl.types.access_control_service
    self.legacy = orb:narrow(facet, oldtypes.IAccessControlService)
  end
end

function Connection:buildChain(chain, caller)
  if chain ~= nil and chain.caller.id == caller.id then
    return chain
  end
end

function Connection:joinedChainFor(remoteid, chain)
  if remoteid ~= BusLogin then
    local access = self.AccessControl
    repeat
      chain = access:signChainFor(remoteid)
      local login = getLogin(self)
      if login == nil then
        sysexthrow.NO_PERMISSION{
          completed = "COMPLETED_NO",
          minor = loginconst.NoLoginCode,
        }
      end
    until unmarshalChain(self, chain).caller.id == login.id
  end
  return chain
end

function Connection:sendrequest(request)
  local login = getLogin(self)
  if login ~= nil then
    request.login = login
    sendBusRequest(self, request)
  else
    setNoPermSysEx(request, loginconst.NoLoginCode)
    log:exception(msg.AttemptToCallWhileNotLoggedIn:tag{
      operation = request.operation_name,
    })
  end
end

function Connection:receivereply(request)
  receiveBusReply(self, request)
  if request.success == false then
    local except = request.results[1]
    if except._repid == sysex.NO_PERMISSION
    and except.completed == "COMPLETED_NO"
    and except.minor == loginconst.InvalidLoginCode then
      local invlogin = request.login
      if self.login == invlogin then
        localLogout(self)
        self.invalidLogin = invlogin
      end
      log:exception(msg.GotInvalidLoginException:tag{
        operation = request.operation_name,
        login = invlogin.id,
        entity = invlogin.entity,
      })
      local login = getLogin(self)
      if login ~= nil then
        request.success = nil -- reissue request to the same reference
        log:action(msg.ReissueCallAfterInvalidLogin:tag{
          operation = request.operation_name,
          login = login.id,
          entity = login.entity,
        })
      else
        except.minor = loginconst.NoLoginCode
      end
    end
  end
end

function Connection:receiverequest(request)
  if self.login ~= nil then
    local ok, ex = pcall(receiveBusRequest, self, request)
    if ok then
      if request.success == nil and self:getCallerChain() == nil then
        log:exception(msg.DeniedOrdinaryCall:tag{
          operation = request.operation.name,
        })
        setNoPermSysEx(request, loginconst.NoCredentialCode)
      end
    else
      if ex._repid == sysex.NO_PERMISSION
      and ex.completed == "COMPLETED_NO"
      and ex.minor == loginconst.NoLoginCode
      then
        log:exception(msg.LostLoginDuringCallDispatch:tag{
          operation = request.operation.name,
        })
        setNoPermSysEx(request, loginconst.UnknownBusCode)
      else
        error(ex)
      end
    end
  else
    log:exception(msg.GotCallWhileNotLoggedIn:tag{
      operation = request.operation_name,
    })
    setNoPermSysEx(request, loginconst.UnknownBusCode)
  end
end


function Connection:loginByPassword(entity, password)
  if self.login ~= nil then error(msg.AlreadyLoggedIn) end
  local access = self.AccessControl
  local pubkey = self.prvkey:encode("public")
  local encoder = self.orb:newencoder()
  encoder:put({data=password,hash=sha256(pubkey)},
    self.types.LoginAuthenticationInfo)
  local encoded = encoder:getdata()
  local encrypted, errmsg = self.buskey:encrypt(encoded)
  if encrypted == nil then
    ServiceFailure{message=msg.InvalidBusKey:tag{ errmsg = errmsg }}
  end
  local login, lease = access:loginByPassword(entity, pubkey, encrypted)
  localLogin(self, access:_get_busid(), login, lease)
  log:request(msg.LoginByPassword:tag{
    login = login.id,
    entity = login.entity,
  })
end

function Connection:loginByCertificate(entity, privatekey)
  if self.login ~= nil then error(msg.AlreadyLoggedIn) end
  local access = self.AccessControl
  local attempt, challenge = access:startLoginByCertificate(entity)
  local secret, errmsg = privatekey:decrypt(challenge)
  if secret == nil then
    attempt:cancel()
    error(msg.WrongPrivateKey:tag{ errmsg = errmsg })
  end
  local pubkey = self.prvkey:encode("public")
  local encoder = self.orb:newencoder()
  encoder:put({data=secret,hash=sha256(pubkey)},
    self.types.LoginAuthenticationInfo)
  local encoded = encoder:getdata()
  local encrypted, errmsg = self.buskey:encrypt(encoded)
  if encrypted == nil then
    attempt:cancel()
    ServiceFailure{ message = msg.InvalidBusKey:tag{ errmsg = errmsg } }
  end
  local login, lease = attempt:login(pubkey, encrypted)
  localLogin(self, access:_get_busid(), login, lease)
  log:request(msg.LoginByCertificate:tag{
    login = login.id,
    entity = login.entity,
  })
end

function Connection:startSharedAuth()
  local attempt, challenge = callWithin(self, self.AccessControl,
                                        "startLoginBySharedAuth")
  local secret, errmsg = self.prvkey:decrypt(challenge)
  if secret == nil then
    attempt:cancel()
    error(msg.CorruptedPrivateKey:tag{ errmsg = errmsg })
  end
  return attempt, secret
end

function Connection:cancelSharedAuth(attempt)
  attempt:cancel()
end

function Connection:loginBySharedAuth(attempt, secret)
  if self.login ~= nil then error(msg.AlreadyLoggedIn) end
  local access = self.AccessControl
  local pubkey = self.prvkey:encode("public")
  local encoder = self.orb:newencoder()
  encoder:put({data=secret,hash=sha256(pubkey)},
    self.types.LoginAuthenticationInfo)
  local encoded = encoder:getdata()
  local encrypted, errmsg = self.buskey:encrypt(encoded)
  if encrypted == nil then
    attempt:cancel()
    error(msg.InvalidBusPublicKey:tag{ errmsg = errmsg })
  end
  local login, lease = attempt:login(pubkey, encrypted)
  localLogin(self, access:_get_busid(), login, lease)
  log:request(msg.LoginBySharedAuth:tag{
    login = login.id,
    entity = login.entity,
  })
end

function Connection:logout()
  local login = self.login
  if login ~= nil then
    log:request(msg.PerformLogout:tag{
      login = login.id,
      entity = login.entity,
    })
    local result, except = pcallWithin(self, self.AccessControl, "logout")
    if not result and(except._repid ~= sysex.NO_PERMISSION
                   or except.minor ~= loginconst.InvalidLoginCode
                   or except.completed ~= "COMPLETED_NO") then error(except) end
    localLogout(self)
    return result
  end
  self.invalidLogin = nil
  return false
end

function Connection:onInvalidLogin()
  -- does nothing by default
end



local IgnoredThreads = {}

local WeakKeys = { __mode="k" }

local ConnectionManager = class()

function ConnectionManager:__init()
  self.requesterOf = setmetatable({}, WeakKeyMeta) -- [thread]=connection
  self.dispatcherOf = {} -- [busid]=connection
end

function ConnectionManager:sendrequest(request)
  if IgnoredThreads[running()] == nil then
    local conn = self.requesterOf[running()] or self.defaultConnection
    if conn ~= nil then
      request.openbusConnection = conn
      conn:sendrequest(request)
    else
      log:exception(msg.AttemptToCallWithoutConnection:tag{
        operation = request.operation_name,
      })
      setNoPermSysEx(request, loginconst.NoLoginCode)
    end
  else
    log:access(self, msg.PerformIgnoredCall:tag{
      operation = request.operation_name,
    })
  end
end

function ConnectionManager:receivereply(request)
  local conn = request.openbusConnection
  if conn ~= nil then
    conn:receivereply(request)
    if request.success ~= nil then
      request.openbusConnection = nil
    end
  end
end

function ConnectionManager:receiverequest(request)
  local busid = getBusId(self, request.service_context)
  local conn = self.dispatcherOf[busid] or self.defaultConnection
  if conn ~= nil then
    request.openbusConnection = conn
    self:setRequester(conn)
    conn:receiverequest(request)
  else
    setNoPermSysEx(request, busid and loginconst.UnknownBusCode or 0)
    log:exception(msg.GotCallWhileDisconnected:tag{
      operation = request.operation_name,
    })
  end
end

function ConnectionManager:sendreply(request)
  local conn = request.openbusConnection
  if conn.sendreply ~= nil then
    request.openbusConnection = nil
    conn:sendreply(request)
  end
end


function ConnectionManager:createConnection(host, port, props)
  if props == nil then props = {} end
  local orb = self.orb
  local legacy = not props.nolegacy
  local delegorig
  if legacy then
    local delegorig = props.legacydelegate
    if delegorig == "originator" then
      delegorig = true
    elseif delegorig ~= nil and delegorig ~= "caller" then
      error(msg.InvalidLegacyDelegateOption:tag{value=delegorig})
    end
    local legacyref = "corbaloc::"..host..":"..port.."/openbus_v1_05"
    legacy = orb:newproxy(legacyref, nil, "scs::core::IComponent")
    if legacy:_non_existent() then
      legacy = nil
      log:exception(msg.BusDoesNotProvideLegacySupport:tag{host=host, port=port})
    end
  end
  local ref = "corbaloc::"..host..":"..port.."/"..BusObjectKey
  return Connection{
    manager = self,
    orb = orb,
    bus = orb:newproxy(ref, nil, "scs::core::IComponent"),
    legacy = legacy,
    legacyDelegOrig = delegorig,
    prvkey = props.privatekey,
  }
end

function ConnectionManager:setDefaultConnection(conn)
  self.defaultConnection = conn
end

function ConnectionManager:getDefaultConnection()
  return self.defaultConnection
end

function ConnectionManager:setRequester(conn)
  self.requesterOf[running()] = conn
end

function ConnectionManager:getRequester()
  return self.requesterOf[running()]
end

function ConnectionManager:setDispatcher(conn)
  self.dispatcherOf[conn.busid] = conn
end

function ConnectionManager:getDispatcher(busid)
  return self.dispatcherOf[busid]
end

function ConnectionManager:clearDispatcher(busid)
  local dispatcherOf = self.dispatcherOf
  local conn = dispatcherOf[busid]
  dispatcherOf[busid] = nil
  return conn
end



-- allow login operations to be performed without credentials
do
  local IgnoredMethods = {
    [Connection] = {
      "loginByPassword",
      "loginByCertificate",
      "loginBySharedAuth",
      "cancelSharedAuth",
    },
    [ConnectionManager] = {
      "createConnection",
    },
  }
  local function continuation(thread, ok, ...)
    IgnoredThreads[thread] = nil
    if not ok then error((...)) end
    return ...
  end
  for class, methods in pairs(IgnoredMethods) do
    for _, name in ipairs(methods) do
      local op = class[name]
      class[name] = function(self, ...)
        local thread = running()
        IgnoredThreads[thread] = true 
        return continuation(thread, pcall(op, self, ...))
      end
    end
  end
end



local openbus = { sleep = delay }

function openbus.newthread(func, ...)
  local thread = newthread(func)
  cothread.next(thread, ...)
  return thread
end

function openbus.initORB(configs)
  local orb = neworb(copy(configs))
  local manager = ConnectionManager{ orb = orb }
  orb.OpenBusConnectionManager = manager
  orb:setinterceptor(manager, "corba")
  return orb
end



-- insert function argument typing
local argcheck = require "openbus.util.argcheck"
argcheck.convertclass(Connection, {
  loginByPassword = { "string", "string" },
  loginByCertificate = { "string", "userdata" },
  logout = {},
  getCallerChain = {},
  joinChain = { "nil|table" },
  exitChain = {},
  getJoinedChain = {},
})
argcheck.convertclass(ConnectionManager, {
  createConnection = { "string", "number|string", "nil|table" },
  setDefaultConnection = { "nil|table" },
  getDefaultConnection = {},
  setRequester = { "nil|table" },
  getRequester = {},
  setDispatcher = { "table" },
  getDispatcher = { "string" },
  clearDispatcher = { "string" },
})
argcheck.convertmodule(openbus, {
  sleep = { "number" },
  newthread = { "function" },
  initORB = { "nil|table" },
})



return openbus
