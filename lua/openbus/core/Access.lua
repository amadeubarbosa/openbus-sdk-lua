local _G = require "_G"
local assert = _G.assert
local ipairs = _G.ipairs
local pairs = _G.pairs
local pcall = _G.pcall
local rawget = _G.rawget
local select = _G.select
local setmetatable = _G.setmetatable
local type = _G.type

local array = require "table"
local unpack = array.unpack or _G.unpack

local coroutine = require "coroutine"
local running = coroutine.running

local string = require "string"
local char = string.char

local math = require "math"
local random = math.random
local randomseed = math.randomseed

local struct = require "struct"
local encode = struct.pack

local socket = require "socket.core"
local gettime = socket.gettime

local table = require "loop.table"
local clear = table.clear
local copy = table.copy
local memoize = table.memoize

local oil = require "oil"
local neworb = oil.init
local CORBAException = require "oil.corba.giop.Exception"
local idl = require "oil.corba.idl"
local OctetSeq = idl.OctetSeq

local hash = require "lce.hash"
local sha256 = hash.sha256
local pubkey = require "lce.pubkey"
local newkey = pubkey.create

local LRUCache = require "loop.collection.LRUCache"

local log = require "openbus.util.logger"
local oo = require "openbus.util.oo"
local class = oo.class
local sysex = require "openbus.util.sysex"
local is_NO_PERMISSION = sysex.is_NO_PERMISSION
local tickets = require "openbus.util.tickets"

local msg = require "openbus.core.messages"
local idl = require "openbus.core.idl"
local loadidl = idl.loadto
local InvalidLoginsException = idl.types.services.access_control.InvalidLogins
local EncryptedBlockSize = idl.const.EncryptedBlockSize
local CredentialContextId = idl.const.credential.CredentialContextId
local loginconst = idl.const.services.access_control
local InvalidChainCode = loginconst.InvalidChainCode
local InvalidCredentialCode = loginconst.InvalidCredentialCode
local InvalidLoginCode = loginconst.InvalidLoginCode
local InvalidPublicKeyCode = loginconst.InvalidPublicKeyCode
local InvalidRemoteCode = loginconst.InvalidRemoteCode
local InvalidTargetCode = loginconst.InvalidTargetCode
local UnknownBusCode = loginconst.UnknownBusCode
local NoLoginCode = loginconst.NoLoginCode
local UnavailableBusCode = loginconst.UnavailableBusCode
local oldidl = require "openbus.core.legacy.idl"
local loadoldidl = oldidl.loadto
local oldconst = oldidl.const.v2_0
local oldtypes = oldidl.types.v2_0
local LegacyCredentialContextId = oldconst.credential.CredentialContextId

assert(EncryptedBlockSize == oldconst.EncryptedBlockSize)
assert(idl.const.HashValueSize == oldconst.HashValueSize)

local repids = {
  CallChain = idl.types.services.access_control.CallChain,
  CredentialData = idl.types.credential.CredentialData,
  CredentialReset = idl.types.credential.CredentialReset,
  LegacyCallChain = oldtypes.services.access_control.CallChain,
  LegacyCredentialData = oldtypes.credential.CredentialData,
  LegacyCredentialReset = oldtypes.credential.CredentialReset,
}
local VersionHeader = char(idl.const.MajorVersion,
                           idl.const.MinorVersion)
local LegacyVersionHeader = char(oldconst.MajorVersion,
                                 oldconst.MinorVersion)
local SecretSize = 16

local NullChar = "\0"
local NullSecret = NullChar:rep(SecretSize)
local NullHash = NullChar:rep(idl.const.HashValueSize)
local NullChain = {
  encoded = "",
  signature = NullChar:rep(EncryptedBlockSize),
  originators = {},
  caller = nil,
}

local WeakKeys = {__mode = "k"}




local function calculateHash(version, secret, ticket, request)
  return sha256(encode(
    "<c2c0I4c0",             -- '<' flag to set to little endian
    version,                 -- 'c2' sequence of exactly 2 chars of a string
    secret,                  -- 'c0' sequence of all chars of a string
    ticket,                  -- 'I4' unsigned integer with 4 bytes
    request.operation_name)) -- 'c0' sequence of all chars of a string
end

randomseed(gettime())
local function newSecret()
  local bytes = {}
  for i=1, SecretSize do bytes[i] = random(0, 255) end
  return char(unpack(bytes))
end

local function setNoPermSysEx(request, minor)
  request.islocal = true
  request.success = false
  request.results = {CORBAException{"NO_PERMISSION",
    completed = "COMPLETED_NO",
    minor = minor,
  }}
end

local function validateCredential(self, credential, login, request)
  local chain = credential.chain
  if chain == nil or chain.target == self.login.entity then
    -- get current credential session
    local session = self.incomingSessions:rawget(credential.session)
    if session ~= nil then
      local version = credential.islegacy and LegacyVersionHeader
                                           or VersionHeader
      local ticket = credential.ticket
      -- validate credential data with session data
      if login.id == session.login
      and credential.hash == calculateHash(version, session.secret, ticket, request)
      and session.tickets:check(ticket) then
        return true
      end
    end
  end
  -- create a new session for the invalid credential
  return false
end

local function validateChain(self, chain, caller)
  if chain ~= nil then
    return chain.busid == self.busid
       and chain.caller.id == caller.id
       and( chain.signature == nil or -- hack for 'openbus.core.services.Access'
            self.buskey:verify(sha256(chain.encoded), chain.signature) )
  end
  return false
end



local Context = class()

-- Fields that must be provided before using the context:
-- orb: OiL ORB to be used to access the bus

-- Optional field that may be provided to configure the interceptor:
-- prvkey: default private key to be used by all connections using this context

function Context:__init()
  local orb = self.orb
  local types = orb.types
  local idltypes = {}
  for name, repid in pairs(repids) do
    idltypes[name] = types:lookup_id(repid)
  end
  self.types = idltypes
  self.callerChainOf = setmetatable({}, WeakKeys) -- [thread] = chain
  self.joinedChainOf = setmetatable({}, WeakKeys) -- [thread] = chain
end

function Context:getCallerChain()
  return self.callerChainOf[running()]
end

function Context:joinChain(chain)
  local thread = running()
  local joinedChainOf = self.joinedChainOf
  local old = joinedChainOf[thread]
  joinedChainOf[thread] = chain or self.callerChainOf[thread] -- or error?
  return old
end

function Context:exitChain()
  local thread = running()
  local joinedChainOf = self.joinedChainOf
  local old = joinedChainOf[thread]
  joinedChainOf[thread] = nil
  return old
end

function Context:getJoinedChain()
  return self.joinedChainOf[running()]
end



local Interceptor = class()

-- Fields that must be provided before using the interceptor:
-- context      : context object to be used to retrieve credential info from
-- busid        : UUID of the bus being accessed
-- buskey       : public key of the bus being accessed
-- AccessControl: AccessControl facet of the bus being accessed
-- LoginRegistry: LoginRegistry facet of the bus being accessed
-- login        : information about the login used to access the bus

-- Optional field that may be provided to configure the interceptor:
-- prvkey: private key associated to the key registered to the login

function Interceptor:__init()
  self:resetCaches()
end

function Interceptor:resetCaches()
  self.profile2login = LRUCache() -- [iop_profile] = loginid
  self.outgoingSessions = LRUCache()
  self.incomingSessions = LRUCache{
    retrieve = function(id)
      return {
        id = id,
        secret = newSecret(),
        tickets = tickets(),
      }
    end,
  }
end

function Interceptor:unmarshalSignedChain(chain, idltype)
  local encoded = chain.encoded
  if encoded ~= "" then
    local context = self.context
    local types = context.types
    local orb = context.orb
    local decoder = orb:newdecoder(chain.encoded)
    local decoded = decoder:get(idltype)
    local originators = decoded.originators
    originators.n = nil -- remove field 'n' created by OiL unmarshal
    chain.originators = originators
    chain.caller = decoded.caller
    chain.target = decoded.target
    chain.busid = decoded.bus
    return chain
  end
end

local unmarshalSignedChain = Interceptor.unmarshalSignedChain
function Interceptor:unmarshalCredential(contexts)
  local context = self.context
  local types = context.types
  local orb = context.orb
  local credential
  local data = contexts[CredentialContextId]
  if data ~= nil then
    credential = orb:newdecoder(data):get(types.CredentialData)
    credential.chain = unmarshalSignedChain(self, credential.chain,
                                                  types.CallChain)
  elseif self.legacy ~= nil then
    data = contexts[LegacyCredentialContextId]
    if data ~= nil then
      credential = orb:newdecoder(data):get(types.LegacyCredentialData)
      credential.islegacy = true
      credential.chain = unmarshalSignedChain(self, credential.chain,
                                                    types.LegacyCallChain)
      if credential.chain ~= nil then
        credential.chain.busid = credential.bus
        credential.chain.islegacy = true
      end
    end
  end
  return credential
end



function Interceptor:sendrequest(request)
  local contexts = {}
  local context = self.context
  local orb = context.orb
  local sessionid, ticket, hash, signed = 0, 0, NullHash, NullChain
  local idltype, contextid
  local profile2login = self.profile2login
  local target = profile2login:get(request.profile_data)
  if target ~= nil then
    local session = self.outgoingSessions:get(target)
    if session ~= nil then -- credential session is established
      local chain = context.joinedChainOf[running()] or NullChain
      local entity = session.entity
      local ok, result, hashheader
      local islegacy = session.islegacy
      if islegacy then
        local legacy = self.legacy
        ok, result = pcall(legacy.signChainFor, legacy, target, chain)
        if not ok then
          if result._repid == InvalidLoginsException then
            for profile_data, profile_target in pairs(profile2login.map) do
              if target == profile_target then
                profile2login:remove(profile_data)
              end
            end
            setNoPermSysEx(request, InvalidTargetCode)
            return
          end
        end
      elseif chain.islegacy and self.legacy == nil then
        log:exception(msg.LegacyChainNotAllowed:tag{
          target = target,
          entity = entity,
          chain = chain,
        })
        setNoPermSysEx(request, InvalidChainCode)
        return
      else
        ok, result, islegacy = pcall(self.signChainFor, self, entity, chain)
      end
      if not ok then
        log:exception(msg.UnableToSignChainForTarget:tag{
          error = result,
          target = target,
          entity = entity,
          chain = (chain~=NullChain) and chain or nil,
        })
        setNoPermSysEx(request, UnavailableBusCode)
        return
      end
      if islegacy then
        idltype = context.types.LegacyCredentialData
        contextid = LegacyCredentialContextId
        hashheader = LegacyVersionHeader
      else
        idltype = context.types.CredentialData
        contextid = CredentialContextId
        hashheader = VersionHeader
      end
      signed = result
      sessionid = session.id
      ticket = session.ticket+1
      session.ticket = ticket
      hash = calculateHash(hashheader, session.secret, ticket, request)
      log:access(self, msg.PerformBusCall:tag{
        operation = request.operation_name,
        remote = target,
        islegacy = session.islegacy,
      })
    else
      log:access(self, msg.ReinitiateCredentialSession:tag{
        operation = request.operation_name,
      })
    end
  else
    log:access(self, msg.InitiateCredentialSession:tag{
      operation = request.operation_name,
    })
  end
  -- marshal credential information
  local credential = {
    bus = self.busid,
    login = self.login.id,
    session = sessionid,
    ticket = ticket,
    hash = hash,
    chain = signed,
  }
  local encoder = orb:newencoder()
  encoder:put(credential, idltype or context.types.CredentialData)
  contexts[contextid or CredentialContextId] = encoder:getdata()
  if contextid == nil and self.legacy ~= nil then
    contexts[LegacyCredentialContextId] = contexts[CredentialContextId]
  end
  request.service_context = contexts
end

local ExclusivelyLocal = {
  [NoLoginCode] = true,
  [InvalidRemoteCode] = true,
  [UnavailableBusCode] = true,
  [InvalidTargetCode] = true,
}

function Interceptor:receivereply(request)
  if not request.success then
    local except = request.results[1]
    if is_NO_PERMISSION(except, nil, "COMPLETED_NO") then
      if except.minor == InvalidCredentialCode then
        -- got invalid credential exception
        -- extract credential reset
        local reset, islegacy
        local context = self.context
        local orb = context.orb
        local types = context.types
        local service_contexts = request.reply_service_context
        local data = service_contexts[CredentialContextId]
        if data ~= nil then
          reset = orb:newdecoder(data):get(types.CredentialReset)
        elseif self.legacy ~= nil then
          local data = service_contexts[LegacyCredentialContextId]
          if data ~= nil then
            reset = orb:newdecoder(data):get(types.LegacyCredentialReset)
            local backup = context:exitChain()
            local target = self.LoginRegistry:getLoginEntry(reset.target)
            if backup ~= nil then context:joinChain(backup) end
            if target == nil then
              log:exception(msg.UnableToGetTargetEntity:tag{
                target = reset.target,
              })
              except.minor = InvalidTargetCode
              return
            end
            reset.entity = target.entity
            islegacy = true
          end
        end
        -- validate credential reset
        if reset ~= nil then
          local secret, errmsg = self.prvkey:decrypt(reset.challenge)
          if secret ~= nil then
            local target = reset.target
            local entity = reset.entity
            log:access(self, msg.GotCredentialReset:tag{
              operation = request.operation_name,
              entity = entity,
              remote = target,
              islegacy = islegacy,
            })
            reset.secret = secret
            -- initialize session and set credential session information
            self.profile2login:put(request.profile_data, target)
            self.outgoingSessions:put(target, {
              id = reset.session,
              secret = reset.secret,
              remote = target,
              entity = entity,
              ticket = -1,
              islegacy = islegacy,
            })
            request.success = nil -- reissue request to the same reference
          else
            log:exception(msg.GotCredentialResetWithBadChallenge:tag{
              operation = request.operation_name,
              remote = reset.target,
              error = errmsg,
            })
            except.minor = InvalidRemoteCode
          end
        else
          log:exception(msg.CredentialResetMissing:tag{
            operation = request.operation_name,
          })
          except.minor = InvalidRemoteCode
        end
      elseif not request.islocal and ExclusivelyLocal[except.minor] ~= nil then
        log:exception(msg.IllegalUseOfLocalMinorCodeByRemoteSite:tag{
          operation = request.operation_name,
          codeused = except.minor,
        })
        except.minor = InvalidRemoteCode
      end
    end
  end
end

function Interceptor:receiverequest(request, credential)
  local credential = credential
                  or self:unmarshalCredential(request.service_context)
  if credential ~= nil then
    local busid = credential.bus
    if busid == self.busid then
      local caller = self.LoginRegistry:getLoginEntry(credential.login)
      if caller ~= nil then
        local context = self.context
        if validateCredential(self, credential, caller, request) then
          local chain = credential.chain
          if validateChain(self, chain, caller) then
            log:access(self, msg.GotBusCall:tag{
              operation = request.operation_name,
              remote = caller.id,
              entity = caller.entity,
              islegacy = credential.islegacy,
            })
            context.callerChainOf[running()] = chain
          else
            -- invalid call chain
            log:exception(msg.GotCallWithInvalidChain:tag{
              operation = request.operation_name,
              remote = caller.id,
              entity = caller.entity,
              islegacy = credential.islegacy,
            })
            setNoPermSysEx(request, InvalidChainCode)
          end
        else
          -- invalid credential, try to reset credetial session
          local sessions = self.incomingSessions
          local newsession = sessions:get(#sessions.map+1)
          newsession.login = caller.id
          local challenge, errmsg = caller.pubkey:encrypt(newsession.secret)
          if challenge ~= nil then
            -- marshall credential reset
            log:access(self, msg.SendCredentialReset:tag{
              operation = request.operation_name,
              remote = caller.id,
              entity = caller.entity,
              islegacy = credential.islegacy,
            })
            local login = self.login
            local encoder = context.orb:newencoder()
            local idltype = context.types.CredentialReset
            local contextid = CredentialContextId
            if credential.islegacy then
              idltype = context.types.LegacyCredentialReset
              contextid = LegacyCredentialContextId
            end
            encoder:put({
              target = login.id,
              entity = login.entity,
              session = newsession.id,
              challenge = challenge,
            }, idltype)
            request.reply_service_context = { [contextid] = encoder:getdata() }
            setNoPermSysEx(request, InvalidCredentialCode)
          else
            log:exception(msg.UnableToEncryptSecretWithCallerKey:tag{
              operation = request.operation_name,
              remote = caller.id,
              entity = caller.entity,
              error = errmsg,
            })
            setNoPermSysEx(request, InvalidPublicKeyCode)
          end
        end
      else
        -- credential with invalid login
        log:exception(msg.GotCallWithInvalidLogin:tag{
          operation = request.operation_name,
          remote = credential.login,
        })
        setNoPermSysEx(request, InvalidLoginCode)
      end
    else
      -- credential for another bus
      log:exception(msg.GotCallFromAnotherBus:tag{
        operation = request.operation_name,
        remote = credential.login,
        bus = busid,
      })
      setNoPermSysEx(request, UnknownBusCode)
    end
  else
    log:access(self, msg.GotOrdinaryCall:tag{
      operation = request.operation_name,
    })
  end
end

function Interceptor:sendreply()
  self.context.callerChainOf[running()] = nil
end



function log.custom:access(conn, ...)
  local viewer = self.viewer
  local output = viewer.output
  if self.flags.multiplex ~= nil then
    local login, busid = conn.login, conn.busid
    if login ~= nil then
      output:write(msg.CurrentLogin:tag{
        bus = busid,
        login = login.id,
        entity = login.entity,
      },"  ")
    end
  end
  for i = 1, select("#", ...) do
    local value = select(i, ...)
    if type(value) == "string"
      then output:write(value)
      else viewer:write(value)
    end
  end
end



local module = {
  Context = Context,
  Interceptor = Interceptor,
  setNoPermSysEx = setNoPermSysEx,
}

function module.initORB(configs)
  if configs == nil then
    configs = {}
  end
  if configs.options == nil then
    configs.options = {}
  end
  if configs.options.tcp == nil then
    configs.options.tcp = {reuseaddr=true}
  end
  if configs.flavor == nil then
    configs.flavor = "cooperative;corba.intercepted"
  end
  local orb = neworb(configs)
  loadidl(orb)
  loadoldidl(orb)
  return orb
end

return module
