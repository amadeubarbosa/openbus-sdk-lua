local _G = require "_G"
local ipairs = _G.ipairs
local pairs = _G.pairs
local pcall = _G.pcall
local rawget = _G.rawget
local setmetatable = _G.setmetatable
local unpack = _G.unpack

local cothread = require "cothread"
local running = cothread.running

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
local repids = {
  CallChain = idl.types.services.access_control.CallChain,
  CredentialData = idl.types.credential.CredentialData,
  CredentialReset = idl.types.credential.CredentialReset,
}
local VersionHeader = char(idl.const.MajorVersion,
                           idl.const.MinorVersion)

local SecretSize = 16

local NullChar = "\0"
local NullSecret = NullChar:rep(SecretSize)
local NullHash = NullChar:rep(idl.const.HashValueSize)
local NullChain = {
  encoded = "",
  signature = NullChar:rep(EncryptedBlockSize),
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
  request.results = {{
    _repid = sysex.NO_PERMISSION,
    completed = "COMPLETED_NO",
    minor = minor,
  }}
end

local function marshalCredential(self, request, credential, chain, remoteid)
  local orb = self.orb
  local legacy = self.legacy
  local contexts = {}
  if chain==nil or chain.signature~=nil then -- no legacy chain (OpenBus 1.5)
    if remoteid then -- credential session is established
      legacy = false -- do not send legacy credential (OpenBus 1.5)
      if remoteid ~= self.busid then
        if chain == nil then chain = self.emptyChain end
        chain = self.signedChainOf[chain]:get(remoteid)
      end
    end
    credential.chain = chain or NullChain
    local encoder = self.orb:newencoder()
    encoder:put(credential, self.types.CredentialData)
    contexts[CredentialContextId] = encoder:getdata()
  end
  if legacy then
    local encoder = orb:newencoder()
    local login = self.login
    encoder:string(login.id)
    encoder:string(login.entity)
    local callers = chain and chain.callers
    if callers ~= nil and #callers > 1 then
      encoder:string(callers[1].entity)
    else
      encoder:string("")
    end
    contexts[1234] = encoder:getdata()
  end
  request.service_context = contexts
end

local function unmarshalCredential(self, contexts)
  local types = self.types
  local orb = self.orb
  local data = contexts[CredentialContextId]
  if data ~= nil then
    local credential = self.orb:newdecoder(data):get(types.CredentialData)
    if credential ~= nil then
      local chain = credential.chain
      local encoded = chain.encoded
      if encoded == "" then
        chain = nil
      else
        local decoder = orb:newdecoder(encoded)
        local decoded = decoder:get(types.CallChain)
        local callers = decoded.callers
        callers.n = nil -- remove field 'n' created by OiL unmarshal
        chain.callers = callers
        chain.target = decoded.target
        chain.busid = credential.bus
      end
      return credential, chain
    end
  end
  if self.legacy then
    local data = contexts[1234]
    if data ~= nil then
      local decoder = orb:newdecoder(data)
      local loginId = decoder:string()
      local entity = decoder:string()
      local callers = {{id=loginId, entity=entity}}
      local delegate = decoder:string()
      if delegate ~= "" then
        callers[1], callers[2] = {id="<unknown>",entity=delegate},callers[1]
      end
      return {
        bus = nil,
        login = loginId,
        ticket = nil,
        hash = nil,
      }, {
        encoded = nil,
        signature = nil,
        target = nil,
        callers = callers,
      }
    end
  end
end

local function marshalReset(self, request, sessionid, challenge)
  local encoder = self.orb:newencoder()
  encoder:put({
    login = self.login.id,
    session = sessionid,
    challenge = challenge,
  }, self.types.CredentialReset)
  request.reply_service_context = {
    [CredentialContextId] = encoder:getdata(),
  }
end

local function unmarshalReset(self, request)
  local data = request.reply_service_context[CredentialContextId]
  if data ~= nil then
    local reset = self.orb:newdecoder(data):get(self.types.CredentialReset)
    if reset ~= nil then
      local login = reset.login
      local secret, errmsg = self.prvkey:decrypt(reset.challenge)
      if secret ~= nil then
        reset.secret = secret
        return reset
      else
        log:badaccess(msg.CredentialResetBadChallenge:tag{
          operation = request.operation_name,
          error = errmsg,
        })
      end
    else
      log:badaccess(msg.CredentialResetUnsupportedVersion:tag{
        operation = request.operation_name,
        major = major,
        minor = minor,
      })
    end
  else
    log:badaccess(msg.CredentialResetMissing:tag{
      operation = request.operation_name,
    })
  end
end



local Interceptor = class()

-- Fields that must be provided before using the interceptor:
-- orb          : OiL ORB to be used to access the bus
-- busid        : UUID of the bus being accessed
-- buskey       : public key of the bus being accessed
-- AccessControl: AccessControl facet of the bus being accessed
-- logins       : LoginRegistry facet of the bus being accessed
-- login        : information about the login used to access the bus

-- Optional field that may be provided to configure the interceptor:
-- prvkey     : private key associated to the key registered to this login
-- legacy     : flag indicating whether to accept OpenBus 1.5 invocations

function Interceptor:__init()
  if self.prvkey == nil then self.prvkey = newkey(EncryptedBlockSize) end
  local types = self.orb.types
  local idltypes = {}
  for name, repid in pairs(repids) do
    idltypes[name] = types:lookup_id(repid)
  end
  self.types = idltypes
  self:resetCaches()
end

function Interceptor:resetCaches()
  self.emptyChain = { callers = {} }
  self.callerChainOf = setmetatable({}, WeakKeys) -- [thread] = callerChain
  self.joinedChainOf = setmetatable({}, WeakKeys) -- [thread] = joinedChain
  self.signedChainOf = memoize(function(chain) -- [chain] = SignedChainCache
    return LRUCache{
      retrieve = function(remoteid)
        return self:joinedChainFor(remoteid, chain)
      end,
    }
  end, "k")
  self.profile2login = LRUCache()
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

function Interceptor:validateCredential(credential, request, remotekey)
  -- check if is a OpenBus 1.5 credential
  local hash = credential.hash
  if hash == nil then
    return true
  end
  -- get current credential session
  local session = self.incomingSessions:rawget(credential.session)
  if session ~= nil then
    local ticket = credential.ticket
    -- validate credential with current secret
    if hash == calculateHash(session.secret, ticket, request)
    and session.tickets:check(ticket) then
      return true
    end
  end
  -- create a new session for the invalid credential
  return false
end

function Interceptor:validateChain(chain, caller)
  if chain ~= nil then
    if chain.signature ~= nil then -- is not a legacy chain (OpenBus 1.5)
                                   -- legacy chain is always created correctly
      local signed = self.buskey:verify(sha256(chain.encoded), chain.signature)
      if signed and chain.target == self.login.id then
        local callers = chain.callers
        if callers[#callers].id ~= caller.id then
          chain = nil -- invalid chain: last caller is not the current caller
        end
      else
        chain = nil -- invalid chain: unsigned or not for me
      end
    end
  end
  return chain
end

function Interceptor:joinedChainFor(remoteid)
  return self.AccessControl:signChainFor(remoteid)
end



function Interceptor:getCallerChain()
  return self.callerChainOf[running()]
end

function Interceptor:joinChain(chain)
  local thread = running()
  self.joinedChainOf[thread] = chain or self.callerChainOf[thread] -- or error?
end

function Interceptor:exitChain()
  self.joinedChainOf[running()] = nil
end

function Interceptor:getJoinedChain()
  return self.joinedChainOf[running()]
end



function Interceptor:sendrequest(request)
  -- check whether there is an active login
  local login = self.login
  if login ~= nil then
    -- check whether there is an active credential session for this IOR profile
    local sessionid, ticket, hash
    local remoteid = self.profile2login:get(request.profile_data)
    if remoteid then
      local session = self.outgoingSessions:get(remoteid)
      sessionid = session.id
      ticket = session.ticket+1
      session.ticket = ticket
      hash = calculateHash(session.secret, ticket, request)
      log:access(msg.BusCall:tag{
        login = remoteid,
        operation = request.operation_name,
      })
    else
      sessionid = 0
      ticket = 0
      hash = NullHash
      log:access(msg.InitializingCredentialSession:tag{
        operation = request.operation_name,
      })
    end
    local credential = {
      bus = self.busid,
      login = login.id,
      session = sessionid,
      ticket = ticket,
      hash = hash,
    }
    local chain = self.joinedChainOf[running()]
    -- marshal credential information
    marshalCredential(self, request, credential, chain, remoteid)
  else
    -- not logged in yet
    log:badaccess(msg.CallWithoutCredential:tag{
      operation = request.operation_name,
    })
  end
end

function Interceptor:receivereply(request)
  if not request.success then
    local except = request.results[1]
    if except._repid == sysex.NO_PERMISSION
    and except.completed == "COMPLETED_NO"
    and except.minor == loginconst.InvalidCredentialCode then
      -- got invalid credential exception
      local reset = unmarshalReset(self, request)
      if reset ~= nil then
        -- initialize session and set credential session information
        local remoteid = reset.login
        self.profile2login:put(request.profile_data, remoteid)
        self.outgoingSessions:put(remoteid, {
          id = reset.session,
          secret = reset.secret,
          remoteid = remoteid,
          ticket = -1,
        })
        log:access(msg.CredentialSessionReset:tag{
          login = remoteid,
          operation = request.operation_name,
        })
        request.success = nil -- reissue request to the same reference
      else
        except.minor = loginconst.InvalidRemoteCode
      end
    end
  end
end

function Interceptor:receiverequest(request)
  local login = self.login
  if login ~= nil then
    local credential, chain = unmarshalCredential(self, request.service_context)
    if credential ~= nil then
      local caller = self.logins:getLoginEntry(credential.login)
      if caller ~= nil then
        local valid = self:validateCredential(credential, request)
        if valid then
          chain = self:validateChain(chain, caller)
          if chain ~= nil then
            log:access(msg.GotBusCall:tag{
              login = caller.id,
              entity = caller.entity,
              operation = request.operation_name,
            })
            self.callerChainOf[running()] = chain
          else
            -- return invalid chain exception
            setNoPermSysEx(request, loginconst.InvalidChainCode)
            log:badaccess(msg.GotCallWithInvalidChain:tag{
              login = caller.id,
              entity = caller.entity,
              operation = request.operation_name,
            })
          end
        else
          -- credential not valid, try to reset credetial session
          local sessions = self.incomingSessions
          local newsession = sessions:get(#sessions.map+1)
          local challenge, errmsg = caller.pubkey:encrypt(newsession.secret)
          if challenge ~= nil then
            marshalReset(self, request, newsession.id, challenge)
            setNoPermSysEx(request, loginconst.InvalidCredentialCode)
            log:badaccess(msg.GotCallWithInvalidCredential:tag{
              login = caller.id,
              entity = caller.entity,
              operation = request.operation_name,
            })
          else
            setNoPermSysEx(request, loginconst.InvalidPublicKeyCode)
            log:badaccess(msg.UnableToEncryptSecretWithCallerKey:tag{
              login = caller.id,
              entity = caller.entity,
              operation = request.operation_name,
              error = errmsg,
            })
          end
        end
      else
        -- return invalid login exception
        setNoPermSysEx(request, loginconst.InvalidLoginCode)
        log:badaccess(msg.GotCallWithInvalidLogin:tag{
          login = credential.login,
          operation = request.operation_name,
        })
      end
    else
      log:badaccess(msg.GotCallWithoutCredential:tag{
        operation = request.operation_name,
      })
    end
  else
    log:badaccess(msg.GotCallBeforeLogin:tag{
      operation = request.operation_name,
    })
  end
end

function Interceptor:sendreply()
  self.callerChainOf[running()] = nil
end



local module = {
  Interceptor = Interceptor,
}

function module.initORB(configs)
  if configs == nil then configs = {} end
  if configs.tcpoptions == nil then
    configs.tcpoptions = {reuseaddr = true}
  end
  configs.flavor = "cooperative;corba.intercepted"
  local orb = neworb(configs)
  loadidl(orb)
  return orb
end

return module
