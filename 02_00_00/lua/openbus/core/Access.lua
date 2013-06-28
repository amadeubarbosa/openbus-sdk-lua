local _G = require "_G"
local ipairs = _G.ipairs
local pairs = _G.pairs
local pcall = _G.pcall
local rawget = _G.rawget
local setmetatable = _G.setmetatable
local unpack = _G.unpack

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
local giop = require "oil.corba.giop"
local sysex = giop.SystemExceptionIDs
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
local tickets = require "openbus.util.tickets"

local msg = require "openbus.core.messages"
local idl = require "openbus.core.idl"
local loadidl = idl.loadto
local EncryptedBlockSize = idl.const.EncryptedBlockSize
local CredentialContextId = idl.const.credential.CredentialContextId
local loginconst = idl.const.services.access_control
local oldidl = require "openbus.core.legacy.idl"
local loadoldidl = oldidl.loadto

local repids = {
  CallChain = idl.types.services.access_control.CallChain,
  CredentialData = idl.types.credential.CredentialData,
  CredentialReset = idl.types.credential.CredentialReset,
  LegacyCredential = oldidl.types.access_control_service.Credential,
  LegacyACS = oldidl.types.access_control_service.IAccessControlService,
}
local VersionHeader = char(idl.const.MajorVersion,
                           idl.const.MinorVersion)
local LegacyCredentialContextId = 1234
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




local function calculateHash(secret, ticket, request)
  return sha256(encode(
    "<c2c0I4c0",             -- '<' flag to set to little endian
    VersionHeader,           -- 'c2' sequence of exactly 2 chars of a string
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
  request.success = false
  request.results = {CORBAException{"NO_PERMISSION",
    completed = "COMPLETED_NO",
    minor = minor,
  }}
end

local function validateCredential(self, credential, login, request)
  local hash = credential.hash
  if hash ~= nil then
    local chain = credential.chain
    if chain == nil or chain.target == self.login.entity then
      -- get current credential session
      local session = self.incomingSessions:rawget(credential.session)
      if session ~= nil then
        local ticket = credential.ticket
        -- validate credential data with session data
        if login.id == session.login
        and hash == calculateHash(session.secret, ticket, request)
        and session.tickets:check(ticket) then
          return true
        end
      end
    end
  elseif credential.owner == login.entity then -- got a OpenBus 1.5 credential
    if credential.delegate == "" then
      return true
    end
    local allowLegacyDelegate = login.allowLegacyDelegate
    if allowLegacyDelegate == nil then
      allowLegacyDelegate = self.legacy:isValid(credential)
      login.allowLegacyDelegate = allowLegacyDelegate
    end
    return allowLegacyDelegate
  end
  -- create a new session for the invalid credential
  return false
end

local function validateChain(self, chain, caller)
  if chain ~= nil then
    local signature = chain.signature
    if signature then -- no legacy chain (OpenBus 1.5)
      return self.buskey:verify(sha256(chain.encoded), signature)
         and chain.caller.id == caller.id
    end
    return true
  end
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
  self.joinedChainOf[thread] = chain or self.callerChainOf[thread] -- or error?
end

function Context:exitChain()
  self.joinedChainOf[running()] = nil
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
-- legacy: ACS facet of OpenBus 1.5 to validate legacy invocations

function Interceptor:__init()
  self:resetCaches()
end

function Interceptor:resetCaches()
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

function Interceptor:unmarshalCredential(contexts)
  local context = self.context
  local types = context.types
  local orb = context.orb
  local data = contexts[CredentialContextId]
  if data ~= nil then
    local credential = orb:newdecoder(data):get(types.CredentialData)
    local chain = credential.chain
    local encoded = chain.encoded
    if encoded == "" then
      credential.chain = nil
    else
      local decoder = orb:newdecoder(encoded)
      local decoded = decoder:get(types.CallChain)
      local originators = decoded.originators
      originators.n = nil -- remove field 'n' created by OiL unmarshal
      chain.originators = originators
      chain.caller = decoded.caller
      chain.target = decoded.target
    end
    return credential
  end
  if self.legacy ~= nil then
    local data = contexts[LegacyCredentialContextId]
    if data ~= nil then
      local credential = orb:newdecoder(data):get(types.LegacyCredential)
      local loginId = credential.identifier
      local entity = credential.owner
      local delegate = credential.delegate
      local caller = {id=loginId, entity=entity}
      local originators = {}
      if delegate ~= "" then
        originators[1] = {id="<unknown>",entity=delegate}
      end
      credential.login = loginId
      credential.chain = {
        originators = originators,
        caller = caller,
        target = self.login.entity,
      }
      return credential
    end
  end
end



function Interceptor:sendrequest(request)
  local contexts = {}
  local legacy = self.legacy
  local context = self.context
  local orb = context.orb
  local chain = context.joinedChainOf[running()]
  if chain==nil or chain.signature~=nil then -- no legacy chain (OpenBus 1.5)
    local sessionid, ticket, hash = 0, 0, NullHash
    local session = self.outgoingSessions:get(request.profile_data)
    if session ~= nil then -- credential session is established
      legacy = nil -- do not send legacy credential (OpenBus 1.5)
      chain = self:signChainFor(session.target, chain or NullChain)
      sessionid = session.id
      ticket = session.ticket+1
      session.ticket = ticket
      hash = calculateHash(session.secret, ticket, request)
      log:access(self, msg.PerformBusCall:tag{
        operation = request.operation_name,
        remote = session.target,
      })
    else
      chain = nil
      log:access(self, msg.ReinitiateCredentialSession:tag{
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
      chain = chain or NullChain,
    }
    local encoder = orb:newencoder()
    encoder:put(credential, context.types.CredentialData)
    contexts[CredentialContextId] = encoder:getdata()
  end
  -- marshal legacy credential (OpenBus 1.5)
  if legacy ~= nil then
    local encoder = orb:newencoder()
    local login = self.login
    encoder:string(login.id)
    encoder:string(login.entity)
    if chain == nil then
      encoder:string("")
    elseif #chain.originators > 0 and self.legacyDelegOrig then
      encoder:string(chain.originators[1].entity)
    else
      encoder:string(chain.caller.entity)
    end
    contexts[LegacyCredentialContextId] = encoder:getdata()
  end
  request.service_context = contexts
end

function Interceptor:receivereply(request)
  if not request.success then
    local except = request.results[1]
    if except._repid == sysex.NO_PERMISSION
    and except.completed == "COMPLETED_NO"
    and except.minor == loginconst.InvalidCredentialCode then
      -- got invalid credential exception
      local data = request.reply_service_context[CredentialContextId]
      if data ~= nil then
        local context = self.context
        local decoder = context.orb:newdecoder(data)
        local reset = decoder:get(context.types.CredentialReset)
        local secret, errmsg = self.prvkey:decrypt(reset.challenge)
        if secret ~= nil then
          log:access(self, msg.GotCredentialReset:tag{
            operation = request.operation_name,
            remote = reset.target,
          })
          -- initialize session and set credential session information
          self.outgoingSessions:put(request.profile_data, {
            id = reset.session,
            secret = secret,
            target = reset.target,
            ticket = -1,
          })
          request.success = nil -- reissue request to the same reference
        else
          log:exception(msg.GotCredentialResetWihtBadChallenge:tag{
            operation = request.operation_name,
            remote = reset.login,
            error = errmsg,
          })
          except.minor = loginconst.InvalidRemoteCode
        end
      else
        log:exception(msg.CredentialResetMissing:tag{
          operation = request.operation_name,
        })
        except.minor = loginconst.InvalidRemoteCode
      end
    end
  end
end

function Interceptor:receiverequest(request, credential)
  local credential = credential
                  or self:unmarshalCredential(request.service_context)
  if credential ~= nil then
    local busid = credential.bus
    if busid == nil or busid == self.busid then
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
            })
            chain.busid = busid
            context.callerChainOf[running()] = chain
          else
            -- invalid call chain
            log:exception(msg.GotCallWithInvalidChain:tag{
              operation = request.operation_name,
              remote = caller.id,
              entity = caller.entity,
            })
            setNoPermSysEx(request, loginconst.InvalidChainCode)
          end
        elseif busid == nil then
          -- invalid legacy credential (OpenBus 1.5)
          log:exception(msg.GotLegacyCallWithInvalidCredential:tag{
            operation = request.operation_name,
            remote = caller.id,
            entity = caller.entity,
            delegate = credential.delegate,
          })
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
            })
            local encoder = context.orb:newencoder()
            encoder:put({
              target = self.login.entity,
              session = newsession.id,
              challenge = challenge,
            }, context.types.CredentialReset)
            request.reply_service_context = {
              [CredentialContextId] = encoder:getdata(),
            }
            setNoPermSysEx(request, loginconst.InvalidCredentialCode)
          else
            log:exception(msg.UnableToEncryptSecretWithCallerKey:tag{
              operation = request.operation_name,
              remote = caller.id,
              entity = caller.entity,
              error = errmsg,
            })
            setNoPermSysEx(request, loginconst.InvalidPublicKeyCode)
          end
        end
      elseif busid ~= nil then
        -- credential with invalid login
        log:exception(msg.GotCallWithInvalidLogin:tag{
          operation = request.operation_name,
          remote = credential.login,
        })
        setNoPermSysEx(request, loginconst.InvalidLoginCode)
      else
        -- legacy credential with invalid login (OpenBus 1.5)
        log:exception(msg.GotLegacyCallWithInvalidLogin:tag{
          operation = request.operation_name,
          remote = credential.login,
        })
      end
    else
      -- credential for another bus
      log:exception(msg.GotCallFromAnotherBus:tag{
        operation = request.operation_name,
        remote = credential.login,
        bus = busid,
      })
      setNoPermSysEx(request, loginconst.UnknownBusCode)
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
  if configs == nil then configs = {} end
  if configs.tcpoptions == nil then
    configs.tcpoptions = {reuseaddr = true}
  end
  configs.flavor = "cooperative;corba.intercepted"
  local orb = neworb(configs)
  loadidl(orb)
  loadoldidl(orb)
  return orb
end

return module
