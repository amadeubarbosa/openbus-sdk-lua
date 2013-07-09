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
local running = coroutine.running
local newthread = coroutine.create

local string = require "string"
local strrep = string.rep

local math = require "math"
local inf = math.huge
local max = math.max

local io = require "io"
local openfile = io.open

local hash = require "lce.hash"
local sha256 = hash.sha256
local pubkey = require "lce.pubkey"
local newkey = pubkey.create
local decodeprvkey = pubkey.decodeprivate
local decodepubkey = pubkey.decodepublic

local table = require "loop.table"
local copy = table.copy
local memoize = table.memoize

local LRUCache = require "loop.collection.LRUCache"
local Wrapper = require "loop.object.Wrapper"

local cothread = require "cothread"
local resume = cothread.next
local threadtrap = cothread.trap
local unschedule = cothread.unschedule

local giop = require "oil.corba.giop"
local sysex = giop.SystemExceptionIDs

local log = require "openbus.util.logger"
local msg = require "openbus.util.messages"
local oo = require "openbus.util.oo"
local class = oo.class
local sysexthrow = require "openbus.util.sysex"

local libidl = require "openbus.idl"
local throw = libidl.throw
local coreidl = require "openbus.core.idl"
local BusLogin = coreidl.const.BusLogin
local EncryptedBlockSize = coreidl.const.EncryptedBlockSize
local CredentialContextId = coreidl.const.credential.CredentialContextId
local coresrvtypes = coreidl.types.services
local loginconst = coreidl.const.services.access_control
local logintypes = coreidl.types.services.access_control
local loginthrow = coreidl.throw.services.access_control
local AccessDenied = loginthrow.AccessDenied
local InvalidLogins = loginthrow.InvalidLogins
local BusObjectKey = coreidl.const.BusObjectKey
local ServiceFailure = coreidl.throw.services.ServiceFailure
local access = require "openbus.core.Access"
local neworb = access.initORB
local setNoPermSysEx = access.setNoPermSysEx
local BaseContext = access.Context
local BaseInterceptor = access.Interceptor
local sendBusRequest = BaseInterceptor.sendrequest
local receiveBusReply = BaseInterceptor.receivereply
local receiveBusRequest = BaseInterceptor.receiverequest
local unmarshalCredential = BaseInterceptor.unmarshalCredential

-- must be loaded after OiL is loaded because OiL is the one that installs
-- the cothread plug-in that supports the 'now' operation.
local delay = cothread.delay
local time = cothread.now


local function getLoginEntry(self, loginId)
  local LoginRegistry = self.__object

  -- use the cache to get information about the login
  local cache = self.cache
  local entry = cache:get(loginId)
  if entry == nil then
    local ok, result, enckey = pcall(LoginRegistry.getLoginInfo, LoginRegistry,
                                     loginId)
    entry = cache:get(loginId) -- Check again to see if anything changed
                               -- after the completion of the remote call.
                               -- The information in the cache should be
                               -- more reliable because it must be older
                               -- so the 'deadline' must be more accurate
                               -- than the one would be generated now.
    if entry == nil then
      if ok then
        local pubkey, exception = decodepubkey(enckey)
        if pubkey == nil then
          sysexthrow.NO_PERMISSION{
            completed = "COMPLETED_NO",
            minor = loginconst.InvalidPublicKeyCode,
          }
        end
        entry = result
        entry.encodedkey = enckey
        entry.pubkey = pubkey
        entry.deadline = time() -- valid until this moment
      elseif result._repid == logintypes.InvalidLogins then
        entry = false
      else
        error(result)
      end
      cache:put(loginId, entry)
      return entry or nil
    end
  end

  -- use the cache to validate the login
  if entry then
    if entry.deadline < time() then -- update deadline
      local validity = LoginRegistry:getLoginValidity(loginId)
      if validity <= 0 then
        cache:put(loginId, false)
        return nil -- invalid login
      end
      entry.deadline = time() + validity
    end
    return entry -- valid login
  end
end

local function getLoginValidity(self, loginId)
  local entry = getLoginEntry(self, loginId)
  if entry ~= nil then
    return max(.01, entry.deadline - time())
  end
  return 0
end

local function getLoginInfo(self, loginId)
  local entry = getLoginEntry(self, loginId)
  if entry ~= nil then
    return entry
  end
  InvalidLogins{loginIds={loginId}}
end

local function newLoginRegistryWrapper(LoginRegistry)
  local self = Wrapper{
    __object = LoginRegistry,
    cache = LRUCache(),
    getLoginEntry = getLoginEntry,
    getLoginValidity = getLoginValidity,
    getLoginInfo = getLoginInfo,
  }
  return self
end

local function unmarshalChain(self, signed)
  local context = self.context
  local decoder = context.orb:newdecoder(signed.encoded)
  return decoder:get(context.types.CallChain)
end

local function getDispatcherFor(self, request, credential)
  local callback = self.onCallDispatch
  if callback ~= nil then
    local params = request.parameters
    return callback(self,
      credential.bus,
      credential.login,
      request.object_key,
      request.operation_name,
      unpack(params, 1, params.n))
  end
end

local pcallWithin do
  local function continuation(context, backup, ...)
    context:setCurrentConnection(backup)
    return ...
  end
  function pcallWithin(self, obj, op, ...)
    local context = self.context
    local backup = context:setCurrentConnection(self)
    return continuation(context, backup, pcall(obj[op], obj, ...))
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
  self.context.connectionOf[thread] = self
  log.viewer.labels[thread] = "Login "..self.login.id.." Renewer"
  resume(thread)
end

local function getCoreFacet(self, name, module)
  return self.context.orb:narrow(self.bus:getFacetByName(name),
                                 coresrvtypes[module][name])
end

local function intiateLogin(self)
  local AccessControl = getCoreFacet(self, "AccessControl", "access_control")
  local buskey, errmsg = decodepubkey(AccessControl:_get_buskey())
  if buskey == nil then
    ServiceFailure{message=msg.InvalidBusKey:tag{message=errmsg}}
  end
  return AccessControl, buskey
end

local function encryptLogin(self, buskey, pubkey, data)
  local context = self.context
  local encoder = context.orb:newencoder()
  encoder:put({data=data,hash=sha256(pubkey)},
    context.types.LoginAuthenticationInfo)
  return buskey:encrypt(encoder:getdata())
end

local function localLogin(self, AccessControl, buskey, login, lease)
  local busid = AccessControl:_get_busid()
  local LoginRegistry = getCoreFacet(self, "LoginRegistry", "access_control")
  if self.login ~= nil then throw.AlreadyLoggedIn() end
  self.invalidLogin = nil
  self.busid = busid
  self.buskey = buskey
  self.AccessControl = AccessControl
  self.LoginRegistry = newLoginRegistryWrapper(LoginRegistry)
  self.login = login
  newRenewer(self, lease)
end

local function localLogout(self)
  self.busid = nil
  self.buskey = nil
  self.AccessControl = nil
  self.LoginRegistry = nil
  self.login = nil
  local legacy = self.legacy
  if legacy ~= nil then
    legacy:resetRef()
  end
  self:resetCaches()
  local renewer = self.renewer
  if renewer ~= nil then
    self.renewer = nil
    unschedule(renewer)
  end
end

local function getLogin(self)
  local login = self.login
  if login == nil then
    -- try to recover from an invalid login
    local invlogin = self.invalidLogin
    while invlogin ~= nil do
      local ok, ex = pcall(self.onInvalidLogin, self, invlogin)
      if not ok then
        log:exception(msg.OnInvalidLoginCallbackError:tag{error=ex})
      end
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

local MaxEncryptedData = strrep("\255", EncryptedBlockSize-11)

local function busaddress2component(orb, host, port, key)
  local ref = "corbaloc::"..host..":"..port.."/"..key
  local ok, result = pcall(orb.newproxy, orb, ref, nil, "scs::core::IComponent")
  if not ok then
    throw.InvalidBusAddress{host=host,port=port,message=tostring(result)}
  end
  return result
end



local LegacyACSWrapper = class()

function LegacyACSWrapper:resetRef()
  self.facet = nil
end

function LegacyACSWrapper:isValid(...)
  local facet = self.facet
  if facet == nil then
    local bus = self.bus
    local ok, result = pcall(bus.getFacetByName, bus,
                             "IAccessControlService_v1_05")
    if not ok or result == nil then return end
    facet = result:__narrow(self.idltype)
    self.facet = facet
  end
  local ok, result = pcall(facet.isValid, facet, ...)
  if ok then return result end
  log:exception(msg.UnableToAccessBusLegacySupport:tag{error=result})
end



local Connection = class({}, BaseInterceptor)

function Connection:__init()
  -- retrieve IDL definitions for login
  local legacy = self.legacy
  if legacy ~= nil then
    self.legacy = LegacyACSWrapper{
      idltype = self.context.types.LegacyACS,
      bus = legacy,
    }
  end
end

function Connection:resetCaches()
  BaseInterceptor.resetCaches(self)
  self.signedChainOf = memoize(function(chain) return LRUCache() end, "k")
end

function Connection:signChainFor(target, chain)
  if target == BusLogin then return chain end
  local access = self.AccessControl
  local cache = self.signedChainOf[chain]
  local joined = cache:get(target)
  while joined == nil do
    joined = access:signChainFor(target)
    local login = getLogin(self)
    if login == nil then
      sysexthrow.NO_PERMISSION{
        completed = "COMPLETED_NO",
        minor = loginconst.NoLoginCode,
      }
    end
    cache = self.signedChainOf[chain]
    if unmarshalChain(self, joined).caller.id == login.id then
      cache:put(target, joined)
      break
    end
    joined = cache:get(target)
  end
  return joined
end


function Connection:sendrequest(request)
  local login = getLogin(self)
  if login ~= nil then
    sendBusRequest(self, request)
    request.login = login
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
      if request.success == nil and self.context:getCallerChain() == nil then
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
      elseif ex._repid == sysex.TRANSIENT 
          or ex._repid == sysex.COMM_FAILURE
      then
        log:exception(msg.UnableToVerifyLoginDueToCoreServicesUnaccessible:tag{
          operation = request.operation.name,
        })
        setNoPermSysEx(request, loginconst.UnverifiedLoginCode)
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
  if self.login ~= nil then throw.AlreadyLoggedIn() end
  local AccessControl, buskey = intiateLogin(self)
  local pubkey = self.prvkey:encode("public")
  local encrypted, errmsg = encryptLogin(self, buskey, pubkey, password)
  if encrypted == nil then
    AccessDenied{message=msg.UnableToEncryptPassword:tag{message=errmsg}}
  end
  local login, lease = AccessControl:loginByPassword(entity, pubkey, encrypted)
  localLogin(self, AccessControl, buskey, login, lease)
  log:request(msg.LoginByPassword:tag{
    login = login.id,
    entity = login.entity,
  })
end

function Connection:loginByCertificate(entity, privatekey)
  if self.login ~= nil then throw.AlreadyLoggedIn() end
  local AccessControl, buskey = intiateLogin(self)
  local attempt, challenge = AccessControl:startLoginByCertificate(entity)
  local secret, errmsg = privatekey:decrypt(challenge)
  if secret == nil then
    pcall(attempt.cancel, attempt)
    AccessDenied{message=msg.UnableToDecryptChallenge:tag{message=errmsg}}
  end
  local pubkey = self.prvkey:encode("public")
  local encrypted, errmsg = encryptLogin(self, buskey, pubkey, secret)
  if encrypted == nil then
    pcall(attempt.cancel, attempt)
    ServiceFailure{message=msg.UnableToEncryptSecret:tag{message=errmsg}}
  end
  local ok, login, lease = pcall(attempt.login, attempt, pubkey, encrypted)
  if not ok then
    if login._repid == sysex.OBJECT_NOT_EXIST then
      ServiceFailure{message=msg.UnableToCompleteLoginByCertificateInTime}
    end
    error(login)
  end
  localLogin(self, AccessControl, buskey, login, lease)
  log:request(msg.LoginByCertificate:tag{
    login = login.id,
    entity = login.entity,
  })
end

function Connection:startSharedAuth()
  local AccessControl = self.AccessControl
  if AccessControl == nil then
    sysexthrow.NO_PERMISSION{
      completed = "COMPLETED_NO",
      minor = loginconst.NoLoginCode,
    }
  end
  local attempt, challenge = callWithin(self, AccessControl,
                                        "startLoginBySharedAuth")
  local secret, errmsg = self.prvkey:decrypt(challenge)
  if secret == nil then
    pcall(attempt.cancel, attempt)
    ServiceFailure{message=msg.UnableToDecryptChallenge:tag{message=errmsg}}
  end
  return attempt, secret
end

function Connection:cancelSharedAuth(attempt)
  return pcall(attempt.cancel, attempt)
end

function Connection:loginBySharedAuth(attempt, secret)
  if self.login ~= nil then throw.AlreadyLoggedIn() end
  local AccessControl, buskey = intiateLogin(self)
  local pubkey = self.prvkey:encode("public")
  local encrypted, errmsg = encryptLogin(self, buskey, pubkey, secret)
  if encrypted == nil then
    pcall(attempt.cancel, attempt)
    AccessDenied{message=msg.UnableToEncryptSecret:tag{message=errmsg}}
  end
  local ok, login, lease = pcall(attempt.login, attempt, pubkey, encrypted)
  if not ok then
    if login._repid == sysex.OBJECT_NOT_EXIST then
      throw.InvalidLoginProcess()
    end
    error(login)
  end
  localLogin(self, AccessControl, buskey, login, lease)
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
                   or except.minor ~= loginconst.NoLoginCode
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

local Context = class({}, BaseContext)

function Context:__init()
  if self.prvkey == nil then self.prvkey = newkey(EncryptedBlockSize) end
  self.connectionOf = setmetatable({}, WeakKeys) -- [thread]=connection
  self.types.LoginAuthenticationInfo =
    self.orb.types:lookup_id(logintypes.LoginAuthenticationInfo)
  self.context = self -- to execute 'BaseInterceptor.unmarshalCredential(self)'
  self.legacy = true -- to execute 'BaseInterceptor.unmarshalCredential(self)'
end

function Context:sendrequest(request)
  if IgnoredThreads[running()] == nil then
    local conn = self:getCurrentConnection()
    if conn ~= nil then
      request[self] = conn
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

function Context:receivereply(request)
  local conn = request[self]
  if conn ~= nil then
    conn:receivereply(request)
    if request.success ~= nil then
      request[self] = nil
    end
  end
end

function Context:receiverequest(request)
  local credential = unmarshalCredential(self, request.service_context)
  local conn = getDispatcherFor(self, request, credential)
            or self.defaultConnection
  if conn ~= nil then
    request[self] = conn
    self:setCurrentConnection(conn)
    conn:receiverequest(request, credential)
  else
    log:exception(msg.GotCallWhileDisconnected:tag{
      operation = request.operation_name,
    })
    setNoPermSysEx(request, loginconst.UnknownBusCode)
  end
end

function Context:sendreply(request)
  local conn = request[self]
  if conn ~= nil then
    request[self] = nil
    conn:sendreply(request)
  end
end


function Context:createConnection(host, port, props)
  if props == nil then props = {} end
  local orb = self.orb
  local legacy = not props.nolegacy
  local delegorig
  if legacy then
    local delegorig = props.legacydelegate
    if delegorig == "originator" then
      delegorig = true
    elseif delegorig ~= nil and delegorig ~= "caller" then
      throw.InvalidPropertyValue{property="legacydelegate",value=delegorig}
    end
    legacy = busaddress2component(orb, host, port, "openbus_v1_05")
  end
  -- validate access key if provided
  local prvkey = props.accesskey
  if prvkey ~= nil then
    local result, errmsg = decodepubkey(prvkey:encode("public"))
    if result == nil then
      throw.InvalidPropertyValue{
        property = "accesskey",
        value = msg.UnableToObtainThePublicKey:tag{error=errmsg},
      }
    end
    result, errmsg = result:encrypt(MaxEncryptedData)
    if result == nil then
      throw.InvalidPropertyValue{
        property = "accesskey",
        value = msg.UnableToEncodeDataUsingPublicKey:tag{error=errmsg},
      }
    end
    result, errmsg = prvkey:decrypt(result)
    if result == nil then
      throw.InvalidPropertyValue{
        property = "accesskey",
        value = msg.UnableToDecodeDataUsingTheKey:tag{error=errmsg},
      }
    end
  end
  return Connection{
    context = self,
    orb = orb,
    bus = busaddress2component(orb, host, port, BusObjectKey),
    legacy = legacy,
    legacyDelegOrig = delegorig,
    prvkey = prvkey or self.prvkey,
  }
end

function Context:setDefaultConnection(conn)
  local old = self.defaultConnection
  self.defaultConnection = conn
  return old
end

function Context:getDefaultConnection()
  return self.defaultConnection
end

function Context:setCurrentConnection(conn)
  local connectionOf = self.connectionOf
  local thread = running()
  local old = connectionOf[thread]
  connectionOf[thread] = conn
  return old
end

function Context:getCurrentConnection()
  return self.connectionOf[running()]
      or self.defaultConnection
end

function Context:getLoginRegistry()
  local conn = self:getCurrentConnection()
  if conn == nil or conn.login == nil then
    sysexthrow.NO_PERMISSION{
      completed = "COMPLETED_NO",
      minor = loginconst.NoLoginCode,
    }
  end
  return conn.LoginRegistry
end

local CoreServices = {
  CertificateRegistry = "access_control",
  InterfaceRegistry = "offer_registry",
  EntityRegistry = "offer_registry",
  OfferRegistry = "offer_registry",
}
for name, modname in pairs(CoreServices) do
  Context["get"..name] = function (self)
    local conn = self:getCurrentConnection()
    if conn == nil or conn.login == nil then
      sysexthrow.NO_PERMISSION{
        completed = "COMPLETED_NO",
        minor = loginconst.NoLoginCode,
      }
    end
    return getCoreFacet(conn, name, modname)
  end
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
    [Context] = {
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



local openbus = { sleep = delay, readKey = decodeprvkey }

function openbus.newThread(func, ...)
  local thread = newthread(func)
  cothread.next(thread, ...)
  return thread
end

function openbus.newKey()
  return newkey(EncryptedBlockSize)
end

function openbus.readKeyFile(path)
  local result, errmsg = openfile(path, "rb")
  if result ~= nil then
    local file = result
    result, errmsg = file:read("*a")
    file:close()
    if result ~= nil then
      result, errmsg = decodeprvkey(result)
    end
  end
  return result, errmsg
end

function openbus.initORB(configs)
  local orb = neworb(copy(configs))
  local context = Context{ orb = orb }
  orb.OpenBusContext = context
  orb:setinterceptor(context, "corba")
  return orb
end



-- insert function argument typing
local argcheck = require "openbus.util.argcheck"
argcheck.convertclass(Connection, {
  loginByPassword = { "string", "string" },
  loginByCertificate = { "string", "userdata" },
  startSharedAuth = {},
  cancelSharedAuth = { "table" },
  loginBySharedAuth = { "table", "string" },
  logout = {},
})
local ContextOperations = {
  createConnection = { "string", "number|string", "nil|table" },
  setDefaultConnection = { "nil|table" },
  getDefaultConnection = {},
  setCurrentConnection = { "nil|table" },
  getCurrentConnection = {},
  getCallerChain = {},
  joinChain = { "nil|table" },
  exitChain = {},
  getJoinedChain = {},
  getLoginRegistry = {},
}
for name in pairs(CoreServices) do
  ContextOperations["get"..name] = {}
end
argcheck.convertclass(Context, ContextOperations)
argcheck.convertmodule(openbus, {
  sleep = { "number" },
  newThread = { "function" },
  newKey = {},
  readKey = { "string" },
  readKeyFile = { "string" },
  initORB = { "nil|table" },
})



return openbus
