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

local msg = require "openbus.core.messages"
local idl = require "openbus.core.idl"
local loadidl = idl.loadto
local loginconst = idl.const.services.access_control
local repids = {
	Identifier = idl.types.services.access_control.Identifier,
	LoginInfoSeq = idl.types.services.access_control.LoginInfoSeq,
	EncryptedBlock = idl.types.credential.EncryptedBlock,
	CredentialVersion = idl.types.credential.CredentialVersion,
	CredentialData = idl.types.credential.CredentialData,
	CredentialReset = idl.types.credential.CredentialReset,
}



local NullChar = "\0"
local NullSecret = NullChar:rep(16)
local NullHash = NullChar:rep(32)
local NullSignature = NullChar:rep(256)

local WeakKeys = {__mode = "k"}

local CredentialContextId = 0x42555300 -- "BUS\0"



local CallChain = class()

function CallChain:__init()
	self.joined = LRU(function(login) return false end)
end



local function calculateHash(secret, ticket, request)
	return sha256(encode(
		"<BBc16I4I4c0c0",        -- '<' flag to set to little endian
		2,                       -- 'B' unsigned char
		0,                       -- 'B' unsigned char
		secret,                  -- 'c16' sequence of exactly 16 chars of a string
		ticket,                  -- 'I4' unsigned integer with 4 bytes
		request.request_id,      -- 'I4' unsigned integer with 4 bytes
		request.object_key,      -- 'c0' sequence of all chars of a string
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

local function marshalReset(self, request, challenge)
	local reset = {
		login = self.login.id,
		challenge = challenge,
	}
	local encoder = self.orb:newencoder()
	local types = self.types
	encoder:octet(2)
	encoder:octet(0)
	encoder:put(reset, types.CredentialReset)
	request.service_context = {{
		context_id = CredentialContextId,
		context_data = encoder:getdata(),
	}}
end

local function unmarshalReset(self, contexts)
	for _, context in ipairs(contexts) do
		if context.context_id == CredentialContextId then
			local decoder = self.orb:newdecoder(context.context_data)
			local types = self.types
			local major = decoder:octet()
			local minor = decoder:octet()
			if major == 2 or minor == 0 then
				local reset = decoder:get(types.CredentialReset)
				local login = reset.login
				local secret, errmsg = self.prvkey:decrypt(reset.challenge)
				if secret ~= nil then
					reset.secret = secret
					return reset
				end
				return nil, msg.CredentialResetBadChallenge, { error=errmsg }
			end
			return nil, msg.CredentialResetUnsupportedVersion, {
				major = major,
				minor = minor,
			}
		end
	end
end

local function marshalCredential(self, request, credential, chain, remoteid)
	local orb = self.orb
	local legacy = self.legacy
	local contexts = {nil,nil}
	if chain==nil or chain.signature~=nil then -- no legacy chain (OpenBus 1.5)
		local encoder = orb:newencoder()
		local types = self.types
		encoder:octet(2)
		encoder:octet(0)
		encoder:put(credential, types.CredentialData)
		if remoteid ~= nil then -- credential session is established
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
			if chain ~= nil then
				encoder:put(chain, types.CredentialChain)
			end
		end
		contexts[1] = {
			context_id = CredentialContextId,
			context_data = encoder:getdata(),
		}
	end
	if legacy then
		local encoder = orb:newencoder()
		local login = self.login
		encoder:string(login.id)
		encoder:string(login.entity)
		local callers = chain.callers
		if callers ~= nil and #callers > 1 then
			encoder:string(callers[1].entity)
		else
			encoder:string("")
		end
		contexts[#contexts+1] = {
			context_id = 1234,
			context_data = encoder:getdata(),
		}
	end
	request.service_context = contexts
end

local function unmarshalCredential(self, contexts)
	local types = self.types
	local orb = self.orb
	for _, context in ipairs(contexts) do
		if context.context_id == CredentialContextId then
			local decoder = orb:newdecoder(context.context_data)
			local major = decoder:octet()
			local minor = decoder:octet()
			if major == 2 or minor == 0 then
				local credential = decoder:get(types.CredentialData)
				local chain
				if decoder.cursor <= #decoder.data then
					chain = decoder:get(types.CredentialChain)
					local encoded = chain.encoded
					if encoded ~= nil then
						local types = self.types
						local decoder = self.orb:newdecoder(encoded)
						chain.target = decoder:get(types.Identifier)
						local callers = decoder:get(types.LoginInfoSeq)
						callers.n = nil -- remove field 'n' created by OiL unmarshal
						chain.callers = callers
					end
				end
				return credential, chain
			end
		end
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
	self.emptyChain = CallChain()
	self.callerChainOf = setmetatable({}, WeakKeys)
	self.joinedChainOf = setmetatable({}, WeakKeys)
	self.outgoingCredentials = LRU(function()
		return {
			secret = nil,
			ticket = -1,
		}
	end)
	self.incommingCredentials = LRU(function()
		return {
			secret = newSecret(), -- must be a secret no one can guess
			ticket = -1,
		}
	end)
	local types = self.orb.types
	local idltypes = {}
	for name, repid in pairs(repids) do
		idltypes[name] = types:lookup_id(repid)
	end
	self.types = idltypes
end

function Interceptor:validateCredential(credential, request, remotekey)
	-- check if is a OpenBus 1.5 credential
	local hash = credential.hash
	if hash == nil then
		return true
	end
	-- get current credential session
	local session = self.incommingCredentials[credential.login]
	local ticket = credential.ticket
	-- validate credential with current secret
	if hash == calculateHash(session.secret, ticket, request) then
		return true
	end
	-- validate credential with the last new secret emitted
	local newsecret = session.newsecret
	if newsecret ~= nil and hash == calculateHash(newsecret, ticket, request) then
		session.newsecret = nil
		session.secret = newsecret
		return true
	end
	-- emit a new secret to establish a new session
	newsecret = newSecret()
	session.newsecret = newsecret
	return false, newsecret
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
		local session = self.outgoingCredentials[request.profile_data]
		local ticket = session.ticket+1
		session.ticket = ticket
		local hash
		local secret = session.secret
		if secret == nil then
			hash = NullHash
			log:access(msg.InitializingCredentialSession:tag{
				bus = self.busid,
				login = login.id,
				entity = login.entity,
				operation = request.operation.name,
			})
		else
			hash = calculateHash(secret, ticket, request)
			log:access(msg.BusCall:tag{
				bus = self.busid,
				login = login.id,
				entity = login.entity,
				operation = request.operation.name,
			})
		end
		local credential = {
			bus = self.busid,
			login = login.id,
			ticket = ticket,
			hash = hash,
		}
		local chain = self.joinedChainOf[running()]
		-- marshal credential information
		marshalCredential(self, request, credential, chain, session.remoteid)
	else
		-- not logged in yet
		log:badaccess(msg.CallWithoutCredential:tag{
			operation = request.operation.name,
			bus = self.busid,
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
			local reset, errmsg, tags = unmarshalReset(self, request.service_context)
			if reset ~= nil then
				-- got credential reset information
				local session = self.outgoingCredentials[request.profile_data]
				if session.ticket < 5 then
					-- initialize session
					session.remoteid = reset.login
					session.secret = reset.secret
					log:access(msg.CredentialSessionInitialized:tag{
						bus = self.busid,
						login = self.login.id,
						entity = self.login.entity,
						operation = request.operation.name,
					})
					request.success = nil -- reissue request to the same reference
					return self:sendrequest(request)
				else
					-- too many attempts to establish a session with no success
					log:badaccess(msg.UnableToEstablishCredentialSession:tag{
						bus = self.busid,
						login = self.login.id,
						entity = self.login.entity,
						operation = request.operation.name,
						attempts = session.ticket,
					})
				end
			else
				tags.bus = self.busid
				tags.login = self.login.id
				tags.entity = self.login.entity
				tags.operation = request.operation.name
				log:badaccess(errmsg:tag(tags))
			end
			except.minor = loginconst.InvalidRemoteCode
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
				local valid, newsecret = self:validateCredential(credential, request)
				if valid then
					chain = self:validateChain(chain, caller)
					if chain ~= nil then
						log:access(msg.GotBusCall:tag{
							operation = request.operation.name,
							login = login.id,
							entity = login.entity,
							bus = self.busid,
						})
						self.callerChainOf[running()] = CallChain(chain)
					else
						-- return invalid chain exception
						setNoPermSysEx(request, loginconst.InvalidChainCode)
						tags.bus = self.busid
						tags.login = caller.id
						tags.entity = caller.entity
						tags.operation = request.operation.name
						log:badaccess(errmsg:tag(tags))
					end
				else
					-- credential not valid, try to reset credetial session
					local challenge, errmsg = caller.pubkey:encrypt(newsecret)
					if challenge ~= nil then
						marshalReset(self, request, challenge)
						setNoPermSysEx(request, loginconst.InvalidCredentialCode)
						log:badaccess(msg.GotCallWithInvalidCredential:tag{
							bus = self.busid,
							login = caller.id,
							entity = caller.entity,
							operation = request.operation.name,
						})
					else
						setNoPermSysEx(request, loginconst.InvalidPublicKeyCode)
						log:badaccess(msg.UnableToEncryptSecretWithCallerKey:tag{
							bus = self.busid,
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
					operation = request.operation.name,
					login = caller.id,
					entity = caller.entity,
					bus = self.busid,
				})
			end
		else
			log:badaccess(msg.GotCallWithoutCredential:tag{
				operation = request.operation.name,
				bus = self.busid,
			})
		end
	else
		log:badaccess(msg.GotCallBeforeLogin:tag{
			operation = request.operation.name,
			bus = self.busid,
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
