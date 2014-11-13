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

local array = require "table"
local unpack = array.unpack or _G.unpack

local coroutine = require "coroutine"
local running = coroutine.running
local newthread = coroutine.create

local string = require "string"
local findstring = string.find
local repeatstr = string.rep
local substring = string.sub

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

local log = require "openbus.util.logger"
local msg = require "openbus.util.messages"
local oo = require "openbus.util.oo"
local class = oo.class
local sysex = require "openbus.util.sysex"
local NO_PERMISSION = sysex.NO_PERMISSION
local is_NO_PERMISSION = sysex.is_NO_PERMISSION
local is_TRANSIENT = sysex.is_TRANSIENT
local is_COMM_FAILURE = sysex.is_COMM_FAILURE
local is_OBJECT_NOT_EXIST = sysex.is_OBJECT_NOT_EXIST

local libidl = require "openbus.idl"
local libthrow = libidl.throw
local AlreadyLoggedIn = libthrow.AlreadyLoggedIn
local InvalidBusAddress = libthrow.InvalidBusAddress
local InvalidLoginProcess = libthrow.InvalidLoginProcess
local InvalidPropertyValue = libthrow.InvalidPropertyValue
local InvalidEncodedStream = libthrow.InvalidEncodedStream
local WrongBus = libthrow.WrongBus
local coreidl = require "openbus.core.idl"
local coreconst = coreidl.const
local BusEntity = coreconst.BusEntity
local BusObjectKey = coreconst.BusObjectKey
local EncryptedBlockSize = coreconst.EncryptedBlockSize
local CredentialContextId = coreconst.credential.CredentialContextId
local loginconst = coreconst.services.access_control
local InvalidPublicKeyCode = loginconst.InvalidPublicKeyCode
local NoLoginCode = loginconst.NoLoginCode
local InvalidRemoteCode = loginconst.InvalidRemoteCode
local InvalidLoginCode = loginconst.InvalidLoginCode
local NoCredentialCode = loginconst.NoCredentialCode
local UnknownBusCode = loginconst.UnknownBusCode
local UnverifiedLoginCode = loginconst.UnverifiedLoginCode
local UnavailableBusCode = loginconst.UnavailableBusCode
local coresrvtypes = coreidl.types.services
local logintypes = coresrvtypes.access_control
local AccessControlRepId = logintypes.AccessControl
local LoginRegistryRepId = logintypes.LoginRegistry
local InvalidLoginsRepId = logintypes.InvalidLogins
local LoginAuthenticationInfoRepId = logintypes.LoginAuthenticationInfo
local OfferRegistryRepId = coresrvtypes.offer_registry.OfferRegistry
local coresrvthrow = coreidl.throw.services
local loginthrow = coresrvthrow.access_control
local AccessDenied = loginthrow.AccessDenied
local InvalidLogins = loginthrow.InvalidLogins
local ServiceFailure = coresrvthrow.ServiceFailure
local exportconst = coreidl.const.data_export
local ExportVersion = exportconst.CurrentVersion
local exporttypes = coreidl.types.data_export
local ExportedVersionSeqRepId = exporttypes.ExportedVersionSeq
local ExportedCallChainRepId = exporttypes.ExportedCallChain
local ExportedSharedAuthRepId = exporttypes.ExportedSharedAuth
local access = require "openbus.core.Access"
local neworb = access.initORB
local setNoPermSysEx = access.setNoPermSysEx
local BaseContext = access.Context
local BaseInterceptor = access.Interceptor
local sendBusRequest = BaseInterceptor.sendrequest
local receiveBusReply = BaseInterceptor.receivereply
local receiveBusRequest = BaseInterceptor.receiverequest
local unmarshalCredential = BaseInterceptor.unmarshalCredential
local unmarshalSignedChain = BaseInterceptor.unmarshalSignedChain
local oldidl = require "openbus.core.legacy.idl"
local LegacyAccessControlRepId = oldidl.types.services.access_control.AccessControl
local LegacyExportVersion = oldidl.const.data_export.CurrentVersion
local oldexporttypes = oldidl.types.data_export
local LegacyExportedCallChainRepId = oldexporttypes.ExportedCallChain

-- must be loaded after OiL is loaded because OiL is the one that installs
-- the cothread plug-in that supports the 'now' operation.
cothread.plugin(require "cothread.plugin.sleep")
local delay = cothread.delay
local time = cothread.now

local IComponentRepId = "IDL:scs/core/IComponent:1.0"

do
  local isNoPerm = is_NO_PERMISSION
  function is_NO_PERMISSION(except, minor, completed)
    return isNoPerm(except, minor, completed or "COMPLETED_NO")
  end
end

local function getLoginEntry(self, loginId)
  local LoginRegistry = self.__object

  -- use the cache to get information about the login
  local cache = self.cache
  local entry = cache:get(loginId)
  if entry == nil then
    local ok, result, signedkey = pcall(LoginRegistry.getLoginInfo,
                                        LoginRegistry, loginId)
    entry = cache:get(loginId) -- Check again to see if anything changed
                               -- after the completion of the remote call.
                               -- The information in the cache should be
                               -- more reliable because it must be older
                               -- so the 'deadline' must be more accurate
                               -- than the one would be generated now.
    if entry == nil then
      if ok then
        local enckey = signedkey.encoded
        if not self.buskey:verify(sha256(enckey), signedkey.signature) then
          NO_PERMISSION{
            completed = "COMPLETED_NO",
            minor = loginconst.InvalidPublicKeyCode,
          }
        end
        local pubkey, exception = decodepubkey(enckey)
        if pubkey == nil then
          NO_PERMISSION{
            completed = "COMPLETED_NO",
            minor = InvalidPublicKeyCode,
          }
        end
        entry = result
        entry.encodedkey = enckey
        entry.pubkey = pubkey
        entry.deadline = time() -- valid until this moment
      elseif result._repid == InvalidLoginsRepId then
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

local function getLoginInfo(self, loginId)
  local entry = getLoginEntry(self, loginId)
  if entry ~= nil then
    return entry
  end
  InvalidLogins{loginIds={loginId}}
end

local function newLoginRegistryWrapper(LoginRegistry, buskey)
  local self = Wrapper{
    __object = LoginRegistry,
    cache = LRUCache(),
    buskey = buskey,
    getLoginEntry = getLoginEntry,
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

local function getCoreFacet(self, name, iface)
  return self.context.orb:narrow(self.bus:getFacetByName(name), iface)
end

local function intiateLogin(self)
  local AccessControl = getCoreFacet(self, "AccessControl", AccessControlRepId)
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

local function localLogin(self, AccessControl, busid, buskey, login, lease)
  local LoginRegistry = getCoreFacet(self, "LoginRegistry", LoginRegistryRepId)
  if self.login ~= nil then AlreadyLoggedIn() end
  self.invalidLogin = nil
  self.busid = busid
  self.buskey = buskey
  self.AccessControl = AccessControl
  self.LoginRegistry = newLoginRegistryWrapper(LoginRegistry, buskey)
  self.login = login
  newRenewer(self, lease)
  if self.legacy then
    local legacy = getCoreFacet(self, "LegacySupport", IComponentRepId)
    if legacy ~= nil then
      legacy = legacy:getFacetByName("AccessControl")
      if legacy ~= nil then
        legacy = self.context.orb:narrow(legacy, LegacyAccessControlRepId)
      else
        log:exception(msg.LegacySupportMissing)
      end
    else
      log:exception(msg.LegacySupportNotAvailable)
    end
    self.legacy = legacy
  end
end

local function localLogout(self)
  self.busid = nil
  self.buskey = nil
  self.AccessControl = nil
  self.LoginRegistry = nil
  self.login = nil
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

local MaxEncryptedData = repeatstr("\255", EncryptedBlockSize-11)

local function busaddress2component(orb, host, port, key)
  local ref = "corbaloc::"..host..":"..port.."/"..key
  local ok, result = pcall(orb.newproxy, orb, ref, nil, "scs::core::IComponent")
  if not ok then
    InvalidBusAddress{host=host,port=port,message=tostring(result)}
  end
  return result
end



local SharedAuthSecret = class()

function SharedAuthSecret:__init()
  self.busid = self.bus
end

function SharedAuthSecret:cancel()
  local attempt = self.attempt
  return pcall(attempt.cancel, attempt)
end



local Connection = class({}, BaseInterceptor)

function Connection:resetCaches()
  BaseInterceptor.resetCaches(self)
  self.signedChainOf = memoize(function(chain) return LRUCache() end, "k")
end

local NullChain = {}
function Connection:signChainFor(target, chain)
  if target == BusEntity then return chain, chain.islegacy end
  local access = self.AccessControl
  local cache = self.signedChainOf[chain or NullChain]
  local joined = cache:get(target)
  while joined == nil do
    joined = access:signChainFor(target)
    local login = getLogin(self)
    if login == nil then
      NO_PERMISSION{
        completed = "COMPLETED_NO",
        minor = NoLoginCode,
      }
    end
    cache = self.signedChainOf[chain or NullChain]
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
    setNoPermSysEx(request, NoLoginCode)
    log:exception(msg.AttemptToCallWhileNotLoggedIn:tag{
      operation = request.operation_name,
    })
  end
end

local NoInvalidLoginHandling = {}

function Connection:receivereply(request)
  receiveBusReply(self, request)
  local thread = running()
  if request.success == false and NoInvalidLoginHandling[thread] == nil then
    local except = request.results[1]
    if is_NO_PERMISSION(except, InvalidLoginCode) then
      local invlogin = request.login
      log:exception(msg.GotInvalidLoginException:tag{
        operation = request.operation_name,
        login = invlogin.id,
        entity = invlogin.entity,
      })
      local logins = self.LoginRegistry
      NoInvalidLoginHandling[thread] = true
      local ok, result = pcall(logins.getLoginValidity, logins, invlogin.id)
      NoInvalidLoginHandling[thread] = nil
      if ok and result > 0 then
        log:exception(msg.GotFalseInvalidLogin:tag{
          invlogin = invlogin.id,
        })
        except.minor = InvalidRemoteCode
      elseif ok or is_NO_PERMISSION(result, InvalidLoginCode) then
        if self.login == invlogin then
          localLogout(self)
          self.invalidLogin = invlogin
        end
        request.success = nil -- reissue request to the same reference
        log:action(msg.ReissueCallAfterInvalidLogin:tag{
          operation = request.operation_name,
        })
      else
        log:exception(msg.UnableToVerifyOwnLoginValidity:tag{
          error = result,
          invlogin = invlogin.id,
        })
        except.minor = UnavailableBusCode
      end
    end
  end
end

function Connection:receiverequest(request, ...)
  if self.login ~= nil then
    local ok, ex = pcall(receiveBusRequest, self, request, ...)
    if not ok then
      if is_NO_PERMISSION(ex, NoLoginCode) then
        log:exception(msg.LostLoginDuringCallDispatch:tag{
          operation = request.operation.name,
        })
        setNoPermSysEx(request, UnknownBusCode)
      elseif is_TRANSIENT(ex) or is_COMM_FAILURE(ex) then
        log:exception(msg.UnableToVerifyLoginDueToCoreServicesUnaccessible:tag{
          operation = request.operation.name,
        })
        setNoPermSysEx(request, UnverifiedLoginCode)
      else
        error(ex)
      end
    end
  else
    log:exception(msg.GotCallWhileNotLoggedIn:tag{
      operation = request.operation_name,
    })
    setNoPermSysEx(request, UnknownBusCode)
  end
end


function Connection:loginByPassword(entity, password)
  if self.login ~= nil then AlreadyLoggedIn() end
  local AccessControl, buskey = intiateLogin(self)
  local pubkey = self.prvkey:encode("public")
  local encrypted, errmsg = encryptLogin(self, buskey, pubkey, password)
  if encrypted == nil then
    AccessDenied{message=msg.UnableToEncryptPassword:tag{message=errmsg}}
  end
  local login, lease = AccessControl:loginByPassword(entity, pubkey, encrypted)
  local busid = AccessControl:_get_busid()
  localLogin(self, AccessControl, busid, buskey, login, lease)
  log:request(msg.LoginByPassword:tag{
    login = login.id,
    entity = login.entity,
  })
end

function Connection:loginByCertificate(entity, privatekey)
  if self.login ~= nil then AlreadyLoggedIn() end
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
    if is_OBJECT_NOT_EXIST(login) then
      ServiceFailure{message=msg.UnableToCompleteLoginByCertificateInTime}
    end
    error(login)
  end
  local busid = AccessControl:_get_busid()
  localLogin(self, AccessControl, busid, buskey, login, lease)
  log:request(msg.LoginByCertificate:tag{
    login = login.id,
    entity = login.entity,
  })
end

function Connection:startSharedAuth()
  local AccessControl = self.AccessControl
  if AccessControl == nil then
    NO_PERMISSION{
      completed = "COMPLETED_NO",
      minor = NoLoginCode,
    }
  end
  local attempt, challenge = callWithin(self, AccessControl,
                                        "startLoginBySharedAuth")
  local secret, errmsg = self.prvkey:decrypt(challenge)
  if secret == nil then
    pcall(attempt.cancel, attempt)
    ServiceFailure{message=msg.UnableToDecryptChallenge:tag{message=errmsg}}
  end
  return SharedAuthSecret{
    bus = self.busid,
    attempt = attempt,
    secret = secret,
  }
end

function Connection:loginBySharedAuth(sharedauth)
  if self.login ~= nil then AlreadyLoggedIn() end
  local AccessControl, buskey = intiateLogin(self)
  local busid = AccessControl:_get_busid()
  if busid ~= sharedauth.bus then WrongBus() end
  local attempt = sharedauth.attempt
  local secret = sharedauth.secret
  local pubkey = self.prvkey:encode("public")
  local encrypted, errmsg = encryptLogin(self, buskey, pubkey, secret)
  if encrypted == nil then
    pcall(attempt.cancel, attempt)
    AccessDenied{message=msg.UnableToEncryptSecret:tag{message=errmsg}}
  end
  local ok, login, lease = pcall(attempt.login, attempt, pubkey, encrypted)
  if not ok then
    if is_OBJECT_NOT_EXIST(login) then
      InvalidLoginProcess()
    end
    error(login)
  end
  localLogin(self, AccessControl, busid, buskey, login, lease)
  log:request(msg.LoginBySharedAuth:tag{
    login = login.id,
    entity = login.entity,
  })
end

function Connection:logout()
  local result, except = true
  local login = self.login
  if login ~= nil then
    log:request(msg.PerformLogout:tag{
      login = login.id,
      entity = login.entity,
    })
    local thread = running()
    NoInvalidLoginHandling[thread] = true
    result, except = pcallWithin(self, self.AccessControl, "logout")
    NoInvalidLoginHandling[thread] = nil
    localLogout(self)
    if not result and is_NO_PERMISSION(except, InvalidLoginCode) then
      result, except = true, nil
    end
  end
  self.invalidLogin = nil
  return result, except
end

function Connection:onInvalidLogin()
  -- does nothing by default
end



local NoBusInterception = {}

local WeakKeys = { __mode="k" }

local Context = class({}, BaseContext)

function Context:__init()
  if self.prvkey == nil then self.prvkey = newkey(EncryptedBlockSize) end
  self.connectionOf = setmetatable({}, WeakKeys) -- [thread]=connection
  self.types.LoginAuthenticationInfo =
    self.orb.types:lookup_id(LoginAuthenticationInfoRepId)
  self.types.ExportedVersionSeq =
    self.orb.types:lookup_id(ExportedVersionSeqRepId)
  self.types.ExportedCallChain =
    self.orb.types:lookup_id(ExportedCallChainRepId)
  self.types.ExportedSharedAuth =
    self.orb.types:lookup_id(ExportedSharedAuthRepId)
  self.types.LegacyExportedCallChain =
    self.orb.types:lookup_id(LegacyExportedCallChainRepId)
  -- following are necessary to execute 'BaseInterceptor.unmarshalCredential(self)'
  self.legacy = true
  -- following is necessary to execute 'BaseInterceptor.unmarshalSignedChain(self)'
  self.context = self 
end

function Context:sendrequest(request)
  if NoBusInterception[running()] == nil then
    local conn = self:getCurrentConnection()
    if conn ~= nil then
      request[self] = conn
      conn:sendrequest(request)
    else
      log:exception(msg.AttemptToCallWithoutConnection:tag{
        operation = request.operation_name,
      })
      setNoPermSysEx(request, NoLoginCode)
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
  if credential ~= nil then
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
      setNoPermSysEx(request, UnknownBusCode)
    end
  else
    log:exception(msg.DeniedOrdinaryCall:tag{
      operation = request.operation.name,
    })
    setNoPermSysEx(request, NoCredentialCode)
  end
end

function Context:sendreply(request)
  local conn = request[self]
  if conn ~= nil then
    request[self] = nil
    conn:sendreply(request)
  end
end

function Context:connectByReference(bus, props)
  if props == nil then props = {} end
  -- validate access key if provided
  local prvkey = props.accesskey
  if prvkey ~= nil then
    local result, errmsg = decodepubkey(prvkey:encode("public"))
    if result == nil then
      InvalidPropertyValue{
        property = "accesskey",
        value = msg.UnableToObtainThePublicKey:tag{error=errmsg},
      }
    end
    result, errmsg = result:encrypt(MaxEncryptedData)
    if result == nil then
      InvalidPropertyValue{
        property = "accesskey",
        value = msg.UnableToEncodeDataUsingPublicKey:tag{error=errmsg},
      }
    end
    result, errmsg = prvkey:decrypt(result)
    if result == nil then
      InvalidPropertyValue{
        property = "accesskey",
        value = msg.UnableToDecodeDataUsingTheKey:tag{error=errmsg},
      }
    end
  end
  return Connection{
    context = self,
    orb = self.orb,
    bus = bus,
    prvkey = prvkey or self.prvkey,
    legacy = not props.nolegacy,
  }
end

function Context:connectByAddress(host, port, props)
  if props == nil then props = {} end
  local ref = busaddress2component(self.orb, host, port, BusObjectKey)
  return self:connectByReference(ref, props)
end

Context.createConnection = Context.connectByAddress

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
    NO_PERMISSION{
      completed = "COMPLETED_NO",
      minor = NoLoginCode,
    }
  end
  return conn.LoginRegistry
end

function Context:getOfferRegistry()
  local conn = self:getCurrentConnection()
  if conn == nil or conn.login == nil then
    NO_PERMISSION{
      completed = "COMPLETED_NO",
      minor = NoLoginCode,
    }
  end
  return getCoreFacet(conn, "OfferRegistry", OfferRegistryRepId)
end

function Context:makeChainFor(target)
  local conn = self:getCurrentConnection()
  if conn == nil or conn.login == nil then
    NO_PERMISSION{
      completed = "COMPLETED_NO",
      minor = NoLoginCode,
    }
  end
  local signed = conn:signChainFor(target, self:getJoinedChain())
  return unmarshalSignedChain(self, signed, self.types.CallChain)
end

local EncodingValues = {
  Chain = {
    magictag = exportconst.MagicTag_CallChain,
    pack = function (self, chain)
      if chain.islegacy then -- legacy chain (OpenBus 2.0)
        return LegacyExportVersion, {
          bus = chain.busid,
          signedChain = chain,
        }
      end
      return ExportVersion, chain
    end,
    versions = {
      [ExportVersion] = {
        typename = "ExportedCallChain",
        unpack = function (self, decoded)
          return unmarshalSignedChain(self, decoded,
                                      self.types.CallChain)
        end,
      },
      [LegacyExportVersion] = {
        typename = "LegacyExportedCallChain",
        unpack = function (self, decoded)
          local chain = unmarshalSignedChain(self, decoded.signedChain,
                                             self.types.LegacyCallChain)
          chain.busid = decoded.bus
          return chain
        end,
      },
    },
  },  
  SharedAuth = {
    magictag = exportconst.MagicTag_SharedAuth,
    pack = function (self, secret)
      return ExportVersion, secret
    end,
    versions = {
      [ExportVersion] = {
        typename = "ExportedSharedAuth",
        unpack = function (self, decoded)
          return SharedAuthSecret(decoded)
        end,
      },
    },
  },  
}

for name, info in pairs(EncodingValues) do
  Context["encode"..name] = function (self, value)
    local types = self.types
    local orb = self.orb
    local encoder = orb:newencoder()
    local result, errmsg = info.pack(self, value)
    if result ~= nil then
      local version = result
      result, errmsg = pcall(encoder.put, encoder, errmsg,
                             types[info.versions[version].typename])
      if result then
        local encoded = encoder:getdata()
        encoder = orb:newencoder()
        result, errmsg = pcall(encoder.put, encoder, {{
          version = version,
          encoded = encoded,
        }}, types.ExportedVersionSeq)
        if result then
          return info.magictag..encoder:getdata()
        end
      end
    end
    error(msg.UnableToEncodeChain:tag{ errmsg = errmsg })
  end

  Context["decode"..name] = function (self, stream)
    local magictag = info.magictag
    if findstring(stream, magictag, 1, "no regex") == 1 then
      local types = self.types
      local orb = self.orb
      local decoder = orb:newdecoder(substring(stream, 1+#magictag))
      local ok, result = pcall(decoder.get, decoder, types.ExportedVersionSeq)
      if ok then
        local exports = result
        result = msg.NoSupportedVersionFound
        for _, exported in ipairs(exports) do
          local version = info.versions[exported.version]
          if version ~= nil then
            decoder = orb:newdecoder(exported.encoded)
            ok, result = pcall(decoder.get, decoder, types[version.typename])
            if ok then
              local unpackvalue = version.unpack
              if unpackvalue ~= nil then
                result = unpackvalue(self, result)
              end
              return result
            end
            break
          end
        end
      end
      InvalidEncodedStream{ message = result }
    end
    InvalidEncodedStream{ message = msg.MagicTagNotFound }
  end
end


-- allow login operations to be performed without credentials
do
  local OutsideBusMethods = {
    [SharedAuthSecret] = {
      "cancel",
    },
    [Connection] = {
      "loginByPassword",
      "loginByCertificate",
      "loginBySharedAuth",
    },
    [Context] = {
      "createConnection",
    },
  }
  local function continuation(thread, ok, ...)
    NoBusInterception[thread] = nil
    if not ok then error((...)) end
    return ...
  end
  for class, methods in pairs(OutsideBusMethods) do
    for _, name in ipairs(methods) do
      local op = class[name]
      class[name] = function(self, ...)
        local thread = running()
        NoBusInterception[thread] = true 
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
  if configs == nil then
    configs = {}
  else
    configs = copy(configs)
  end
  local orb = neworb(configs)
  local context = Context{ orb = orb }
  orb.OpenBusContext = context
  orb:setinterceptor(context, "corba")
  return orb
end



-- insert function argument typing
local argcheck = require "openbus.util.argcheck"
argcheck.convertclass(SharedAuthSecret, {
  cancel = {},
})
argcheck.convertclass(Connection, {
  loginByPassword = { "string", "string" },
  loginByCertificate = { "string", "userdata" },
  startSharedAuth = {},
  loginBySharedAuth = { "table" },
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
  getOfferRegistry = {},
  makeChainFor = { "string" },
  encodeChain = { "table" },
  decodeChain = { "string" },
  encodeSharedAuth = { "table" },
  decodeSharedAuth = { "string" },
}
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
