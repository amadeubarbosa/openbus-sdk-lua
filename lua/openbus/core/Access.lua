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

local log = require "openbus.util.logger"
local oo = require "openbus.util.oo"
local class = oo.class
local cache = require "openbus.util.cache"
local LRU = cache.LRU
local tickets = require "openbus.util.tickets"

local msg = require "openbus.core.messages"
local idl = require "openbus.core.idl"
local loadidl = idl.loadto
local loginconst = idl.const.services.access_control
local repids = {
	CallChain = idl.types.services.access_control.CallChain,
	CredentialData = idl.types.credential.CredentialData,
	CredentialReset = idl.types.credential.CredentialReset,
}



local NullChar = "\0"
local NullSecret = NullChar:rep(16)
local NullHash = NullChar:rep(32)
local NullChain = {
	encoded = "",
	signature = NullChar:rep(256),
}

local WeakKeys = {__mode = "k"}

local VersionHeader = "\002\000"
local CredentialContextId = 0x42555300 -- "BUS\0"



local CallChain = class()

function CallChain:__init()
	self.joined = LRU(function(login) return false end)
end



local function calculateHash(secret, ticket, request)
	return sha256(encode(
		"<c2c16I4I4c0",          -- '<' flag to set to little endian
		VersionHeader,           -- 'c2' sequence of exactly 2 chars of a string
		secret,                  -- 'c16' sequence of exactly 16 chars of a string
		ticket,                  -- 'I4' unsigned integer with 4 bytes
		request.request_id,      -- 'I4' unsigned integer with 4 bytes
		request.operation_name)) -- 'c0' sequence of all chars of a string
end

randomseed(gettime())
local function newSecret()
	local bytes = {}
	for i=1, 16 do bytes[i] = random(0, 255) end
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
				local cache = chain.joined
				local joined = cache[remoteid]
				if not joined then
					joined = self:joinedChainFor(remoteid, chain)
					cache[remoteid] = joined
				end
				chain = joined
			end
		end
		credential.chain = chain or NullChain
		local encoder = orb:newencoder()
		encoder:put(credential, self.types.CredentialData)
		contexts[CredentialContextId] = VersionHeader..encoder:getdata()
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
	if data ~= nil and data:find(VersionHeader, 1, true) == 1 then
		local decoder = orb:newdecoder(data:sub(3))
		local credential = decoder:get(types.CredentialData)
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
	if self.legacy then
		for _, context in ipairs(contexts) do
			if context.context_id == 1234 then
				local decoder = orb:newdecoder(context.context_data)
				local loginId = decoder:string()
				local entity = decoder:string()
				local callers = {{id=loginId, entity=entity}}
				local delegate = decoder:string()
				if delegate == "" then
					callers[1], callers[2] = {id="<unknown>",entity=delegate},callers[1]
				end
				return {
					bus = nil,
					login = loginId,
					ticket = nil,
					hash = nil,
				}, CallChain{
					encoded = nil,
					signature = nil,
					target = nil,
					callers = callers,
				}
			end
		end
	end
end

local function marshalReset(self, request, sessionid, challenge)
	local reset = {
		login = self.login.id,
		session = sessionid,
		challenge = challenge,
	}
	local encoder = self.orb:newencoder()
	encoder:put(reset, self.types.CredentialReset)
	request.reply_service_context = {
		[CredentialContextId] = VersionHeader..encoder:getdata(),
	}
end

local function unmarshalReset(self, contexts)
	local data = contexts[CredentialContextId]
	if data ~= nil then
		if data:find(VersionHeader, 1, true) == 1 then
			local decoder = self.orb:newdecoder(data:sub(3))
			local reset = decoder:get(self.types.CredentialReset)
			local login = reset.login
			local secret, errmsg = self.prvkey:decrypt(reset.challenge)
			if secret ~= nil then
				reset.secret = secret
				return reset
			else
				log:badaccess(msg.CredentialResetBadChallenge:tag{
					operation = request.operation.name,
					error = errmsg,
				})
			end
		else
			log:badaccess(msg.CredentialResetUnsupportedVersion:tag{
				operation = request.operation.name,
				major = major,
				minor = minor,
			})
		end
	else
		log:badaccess(msg.CredentialResetMissing:tag{
			operation = request.operation.name,
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
	if self.prvkey == nil then self.prvkey = newkey(256) end
	local types = self.orb.types
	local idltypes = {}
	for name, repid in pairs(repids) do
		idltypes[name] = types:lookup_id(repid)
	end
	self.types = idltypes
	self:resetCaches()
end

function Interceptor:resetCaches()
	self.emptyChain = CallChain{ callers = {} }
	self.callerChainOf = setmetatable({}, WeakKeys)
	self.joinedChainOf = setmetatable({}, WeakKeys)
	self.profile2login = LRU(function() return false end)
	self.outgoingCredentials = LRU(function() return false end)
	self.incomingCredentials = LRU(function(id)
		return {
			id = id,
			secret = newSecret(),
			tickets = tickets(),
		}
	end)
end

function Interceptor:validateCredential(credential, request, remotekey)
	-- check if is a OpenBus 1.5 credential
	local hash = credential.hash
	if hash == nil then
		return true
	end
	-- get current credential session
	local incoming = self.incomingCredentials
	local session = rawget(incoming, credential.session)
	if session ~= nil then
		local ticket = credential.ticket
		-- validate credential with current secret
		if hash == calculateHash(session.secret, ticket, request)
		and session.tickets:check(ticket) then
			return true
		end
	end
	-- create a new session for the invalid credential
	return false, incoming[#incoming+1]
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
		local remoteid = self.profile2login[request.profile_data]
		if remoteid then
			local session = self.outgoingCredentials[remoteid]
			sessionid = session.id
			ticket = session.ticket+1
			session.ticket = ticket
			hash = calculateHash(session.secret, ticket, request)
			log:access(msg.BusCall:tag{
				login = remoteid,
				operation = request.operation.name,
			})
		else
			sessionid = 0
			ticket = 0
			hash = NullHash
			log:access(msg.InitializingCredentialSession:tag{
				operation = request.operation.name,
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
			operation = request.operation.name,
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
			local reset = unmarshalReset(self, request.reply_service_context)
			if reset ~= nil then
				-- get previous credential session information, if any
				local profile = request.profile_data
				local profile2login = self.profile2login
				local previousid = profile2login[profile]
				local remoteid = reset.login
				if previousid ~= remoteid then
					log:badaccess(msg.LoginOfRemoteObjectChanged:tag{
						previous = previousid,
						login = remoteid,
					})
				end
				profile2login[profile] = remoteid
				-- find a suitable credential session
				local outgoing = self.outgoingCredentials
				local session = outgoing[remoteid]
				if not session then
					-- initialize session
					session = {
						id = reset.session,
						secret = reset.secret,
						remoteid = remoteid,
						ticket = -1,
					}
					outgoing[remoteid] = session
					log:access(msg.CredentialSessionInitialized:tag{
						login = remoteid,
						operation = request.operation.name,
					})
				else
					log:access(msg.CredentialSessionReused:tag{
						login = remoteid,
						operation = request.operation.name,
					})
				end
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
				local valid, newsession = self:validateCredential(credential, request)
				if valid then
					chain = self:validateChain(chain, caller)
					if chain ~= nil then
						log:access(msg.GotBusCall:tag{
							login = caller.id,
							entity = caller.entity,
							operation = request.operation.name,
						})
						self.callerChainOf[running()] = CallChain(chain)
					else
						-- return invalid chain exception
						setNoPermSysEx(request, loginconst.InvalidChainCode)
						log:badaccess(msg.GotCallWithInvalidChain:tag{
							login = caller.id,
							entity = caller.entity,
							operation = request.operation.name,
						})
					end
				else
					-- credential not valid, try to reset credetial session
					local challenge, errmsg = caller.pubkey:encrypt(newsession.secret)
					if challenge ~= nil then
						marshalReset(self, request, newsession.id, challenge)
						setNoPermSysEx(request, loginconst.InvalidCredentialCode)
						log:badaccess(msg.GotCallWithInvalidCredential:tag{
							login = caller.id,
							entity = caller.entity,
							operation = request.operation.name,
						})
					else
						setNoPermSysEx(request, loginconst.InvalidPublicKeyCode)
						log:badaccess(msg.UnableToEncryptSecretWithCallerKey:tag{
							login = caller.id,
							entity = caller.entity,
							operation = request.operation.name,
							error = errmsg,
						})
					end
				end
			else
				-- return invalid login exception
				setNoPermSysEx(request, loginconst.InvalidLoginCode)
				log:badaccess(msg.GotCallWithInvalidLogin:tag{
					login = credential.login,
					operation = request.operation.name,
				})
			end
		else
			log:badaccess(msg.GotCallWithoutCredential:tag{
				operation = request.operation.name,
			})
		end
	else
		log:badaccess(msg.GotCallBeforeLogin:tag{
			operation = request.operation.name,
		})
	end
end

function Interceptor:sendreply()
	self.callerChainOf[running()] = nil
end



local module = {
	CallerChain = CallerChain,
	Interceptor = Interceptor,
}

function module.createORB(configs)
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
