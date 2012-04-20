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
local running = coroutine.running

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

local Mutex = require "cothread.Mutex"

local giop = require "oil.corba.giop"
local sysex = giop.SystemExceptionIDs

local log = require "openbus.util.logger"
local msg = require "openbus.util.messages"
local oo = require "openbus.util.oo"
local class = oo.class

local idl = require "openbus.core.idl"
local loginthrow = idl.throw.services.access_control
local loginconst = idl.const.services.access_control
local logintypes = idl.types.services.access_control
local offerconst = idl.const.services.offer_registry
local offertypes = idl.types.services.offer_registry
local BusObjectKey = idl.const.BusObjectKey
local access = require "openbus.core.Access"
local neworb = access.initORB
local CoreInterceptor = access.Interceptor
local sendBusRequest = CoreInterceptor.sendrequest
local receiveBusReply = CoreInterceptor.receivereply
local receiveBusRequest = CoreInterceptor.receiverequest

local oldidl = require "openbus.core.legacy.idl"
local loadoldidl = oldidl.loadto
local oldtypes = oldidl.types.access_control_service

-- must be loaded after OiL is loaded because OiL is the one that installs
-- the cothread plug-in that supports the 'now' operation.
local cothread = require "cothread"
local resume = cothread.next
local unschedule = cothread.unschedule
local deferuntil = cothread.defer
local time = cothread.now
local threadtrap = cothread.trap



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

local function localLogout(self)
  self.login = nil
  self:resetCaches()
  local renewer = self.renewer
  if renewer ~= nil then
    self.renewer = nil
    unschedule(renewer)
  end
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



local WeakKeys = { __mode="k" }

local Interceptor = class()

function Interceptor:__init()
  self.ignoredThreads = setmetatable({}, WeakKeys)
end

function Interceptor:addConnection(conn)
  local current = self.connection
  if current ~= nil then
    error(msg.OrbAlreadyConnectedToBus:tag{bus=current.busid})
  end
  self.connection = conn
end

function Interceptor:removeConnection(conn)
  local current = self.connection
  if current ~= conn then
    error(msg.AttemptToDisconnectInactiveBusConnection)
  end
  self.connection = nil
end

function Interceptor:sendrequest(request)
  if self.ignoredThreads[running()] == nil then
    local conn = self.connection
    if conn ~= nil then
      request.connection = conn
      conn:sendrequest(request)
    else
      request.success = false
      request.results = {self.orb:newexcept{
        "CORBA::NO_PERMISSION",
        completed = "COMPLETED_NO",
        minor = loginconst.NoLoginCode,
      }}
      log:badaccess(msg.CallAfterDisconnection:tag{
        operation = request.operation_name,
      })
    end
  else
    log:access(msg.OutsideBusCall:tag{
      operation = request.operation_name,
    })
  end
end

function Interceptor:receivereply(request)
  local conn = request.connection
  if conn ~= nil then
    conn:receivereply(request)
    if request.success ~= nil then
      request.connection = nil
    end
  end
end

function Interceptor:receiverequest(request)
  local conn = self.connection
  if conn ~= nil then
    request.connection = conn
    conn:receiverequest(request)
  else
    request.success = false
    request.results = {self.orb:newexcept{
      "CORBA::NO_PERMISSION",
      completed = "COMPLETED_NO",
      minor = loginconst.UnverifiedLoginCode,
    }}
    log:badaccess(msg.CallAfterDisconnection:tag{
      operation = request.operation_name,
    })
  end
end

function Interceptor:sendreply(request)
  local conn = request.connection
  if conn.sendreply ~= nil then
    request.connection = nil
    conn:sendreply(request)
  end
end



local Connection = class({}, CoreInterceptor)

function Connection:__init()
  -- retrieve IDL definitions for login
  local orb = self.orb
  self.LoginAuthenticationInfo =
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
  local access = self.AccessControl
  self.busid = access:_get_busid()
  self.buskey = assert(decodepubkey(access:_get_buskey()))
  orb.OpenBusInterceptor:addConnection(self)
  -- create wrapper for core service LoginRegistry
  self.logins = newLoginRegistryWrapper(self.logins)
  
  local legacy = self.legacy
  if legacy ~= nil then
    if legacy:_non_existent() then
      legacy = nil
      log:badaccess(msg.BusWithoutLegacySupport:tag{bus=self.busid})
    else
      local facet = assert(legacy:getFacetByName("ACS_v1_05"))
      if orb.types:lookup_id(oldtypes.IAccessControlService) == nil then
        loadoldidl(orb)
      end
      legacy = orb:narrow(facet, oldtypes.IAccessControlService)
    end
    self.legacy = legacy
  end
end

function Connection:newrenewer(lease)
  local thread
  thread = newthread(function()
    local login = self.login
    local manager = self.AccessControl
    while self.login == login do
      self.renewer = thread
      deferuntil(time()+lease)
      self.renewer = nil
      log:action(msg.RenewLogin:tag{id=login.id,entity=login.entity})
      local ok, result = pcall(manager.renew, manager)
      if ok then
        lease = result
      else
        log:badaccess(msg.FailToRenewLogin:tag{error = result})
      end
    end
  end)
  resume(thread)
  return thread
end


function Connection:sendrequest(request)
  if self.login ~= nil then
    sendBusRequest(self, request)
  else
    request.success = false
    request.results = {self.orb:newexcept{
      "CORBA::NO_PERMISSION",
      completed = "COMPLETED_NO",
      minor = loginconst.NoLoginCode,
    }}
    log:badaccess(msg.CallAfterDisconnection:tag{
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
      log:badaccess(msg.GotInvalidLoginException:tag{
        operation = request.operation_name,
      })
      local login = self.login
      localLogout(self)
      if self:onInvalidLogin(login) then
        request.success = nil -- reissue request to the same reference
        log:badaccess(msg.ReissuingCallAfterCallback:tag{
          operation = request.operation_name,
        })
      end
    end
  end
end

function Connection:receiverequest(request)
  if self:isLoggedIn() then
    receiveBusRequest(self, request)
    if request.success == nil then
      if self:getCallerChain() == nil then
        request.success = false
        request.results = {self.orb:newexcept{
          "CORBA::NO_PERMISSION",
          completed = "COMPLETED_NO",
          minor = loginconst.InvalidLoginCode,
        }}
      end
    end
  else
    log:badaccess(msg.GotCallFromConnectionWithoutLogin:tag{
      operation = request.operation_name,
    })
    request.success = false
    request.results = {self.orb:newexcept{
      "CORBA::NO_PERMISSION",
      completed = "COMPLETED_NO",
      minor = loginconst.UnverifiedLoginCode,
    }}
  end
end


function Connection:loginByPassword(entity, password)
  if self:isLoggedIn() then error(msg.ConnectionAlreadyLogged) end
  local manager = self.AccessControl
  local pubkey = self.prvkey:encode("public")
  local idltype = self.LoginAuthenticationInfo
  local encoder = self.orb:newencoder()
  encoder:put({data=password,hash=sha256(pubkey)}, idltype)
  local encoded = encoder:getdata()
  local encrypted, errmsg = self.buskey:encrypt(encoded)
  if encrypted == nil then
    error(msg.InvalidBusPublicKey:tag{ errmsg = errmsg })
  end
  local login, lease = manager:loginByPassword(entity, pubkey, encrypted)
  self.login = login
  self:newrenewer(lease)
  log:action(msg.LoginByPassword:tag{
    bus = self.busid,
    login = login.id,
    entity = login.entity,
  })
end

function Connection:loginByCertificate(entity, privatekey)
  if self:isLoggedIn() then error(msg.ConnectionAlreadyLogged) end
  local manager = self.AccessControl
  local attempt, challenge = manager:startLoginByCertificate(entity)
  local secret, errmsg = privatekey:decrypt(challenge)
  if secret == nil then
    attempt:cancel()
    error(msg.CorruptedPrivateKey:tag{ errmsg = errmsg })
  end
  local pubkey = self.prvkey:encode("public")
  local idltype = self.LoginAuthenticationInfo
  local encoder = self.orb:newencoder()
  encoder:put({data=secret,hash=sha256(pubkey)}, idltype)
  local encoded = encoder:getdata()
  local encrypted, errmsg = self.buskey:encrypt(encoded)
  if encrypted == nil then
    attempt:cancel()
    error(msg.InvalidBusPublicKey:tag{ errmsg = errmsg })
  end
  local login, lease = attempt:login(pubkey, encrypted)
  self.login = login
  self:newrenewer(lease)
  log:action(msg.LoginByCertificate:tag{
    bus = self.busid,
    login = login.id,
    entity = login.entity,
  })
end

function Connection:startSingleSignOn()
  local manager = self.AccessControl
  local attempt, challenge = manager:startLoginBySingleSignOn()
  local secret, errmsg = self.prvkey:decrypt(challenge)
  if secret == nil then
    attempt:cancel()
    error(msg.CorruptedPrivateKey:tag{ errmsg = errmsg })
  end
  return attempt, secret
end

function Connection:loginBySingleSignOn(attempt, secret)
  if self:isLoggedIn() then error(msg.ConnectionAlreadyLogged) end
  local pubkey = self.prvkey:encode("public")
  local idltype = self.LoginAuthenticationInfo
  local encoder = self.orb:newencoder()
  encoder:put({data=secret,hash=sha256(pubkey)}, idltype)
  local encoded = encoder:getdata()
  local encrypted, errmsg = self.buskey:encrypt(encoded)
  if encrypted == nil then
    attempt:cancel()
    error(msg.InvalidBusPublicKey:tag{ errmsg = errmsg })
  end
  local login, lease = attempt:login(pubkey, encrypted)
  self.login = login
  self:newrenewer(lease)
  log:action(msg.LoginBySingleSignOn:tag{
    bus = self.busid,
    login = login.id,
    entity = login.entity,
  })
end

function Connection:logout()
  if self.login ~= nil then
    local access = self.AccessControl
    local result, except = pcall(access.logout, access)
    if not result and(except._repid ~= sysex.NO_PERMISSION
                   or except.minor ~= loginconst.InvalidLoginCode
                   or except.completed ~= "COMPLETED_NO") then error(except) end
    localLogout(self)
    return result
  end
  return false
end

function Connection:close()
  self:logout()
  self.orb.OpenBusInterceptor:removeConnection(self)
end

function Connection:isLoggedIn()
  return self.login ~= nil
end

function Connection:onInvalidLogin()
  -- does nothing by default
end



-- allow login operations to be performed without credentials
for _, name in ipairs{ "__init", "loginByPassword", "loginByCertificate" } do
  local op = Connection[name]
  Connection[name] = function(self, ...)
    local ignored = self.orb.OpenBusInterceptor.ignoredThreads
    local thread = running()
    ignored[thread] = true 
    local ok, errmsg = pcall(op, self, ...)
    ignored[thread] = nil
    if not ok then error(errmsg) end
  end
end



local function initORB(configs)
  local orb = neworb(copy(configs))
  orb.OpenBusInterceptor = Interceptor{ orb = orb }
  orb:setinterceptor(orb.OpenBusInterceptor, "corba")
  return orb
end

local openbus = { initORB = initORB }

function openbus.connect(host, port, orb)
  if orb == nil then orb = initORB() end
  local ref = "corbaloc::"..host..":"..port.."/"..BusObjectKey
  local legacyref = "corbaloc::"..host..":"..port.."/openbus_v1_05"
  return Connection{
    orb = orb,
    bus = orb:newproxy(ref, nil, "scs::core::IComponent"),
    legacy = orb:newproxy(legacyref, nil, "scs::core::IComponent"),
  }
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
  close = {},
})
argcheck.convertmodule(openbus, {
  initORB = { "nil|table" },
  connect = { "string", "number", "nil|table" },
})



return openbus
