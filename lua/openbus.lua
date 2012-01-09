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

local Wrapper = require "loop.object.Wrapper"

local Mutex = require "cothread.Mutex"

local giop = require "oil.corba.giop"
local sysex = giop.SystemExceptionIDs

local log = require "openbus.util.logger"
local msg = require "openbus.util.messages"
local cache = require "openbus.util.cache"
local LRU = cache.yieldableLRU
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
local neworb = access.createORB
local CoreInterceptor = access.Interceptor
local sendBusRequest = CoreInterceptor.sendrequest
local receiveBusReply = CoreInterceptor.receivereply
local receiveBusRequest = CoreInterceptor.receiverequest

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
	local entry = self.cache(loginId)
	if entry ~= nil then
		local time2live = validity[entry.index]
		if time2live == 0 then
			log:action(msg.InvalidLoginInValidityCache:tag{
				login = loginId,
				entity = entry.entity,
			})
		elseif time2live ~= nil and time2live > time()-timeupdated then
			log:action(msg.ValidLoginInValidityCache:tag{
				login = loginId,
				entity = entry.entity,
			})
			return entry -- valid login in cache
		else -- update validity cache
			log:action(msg.UpdateLoginValidityCache:tag{count=#ids})
			self.timeupdated = time()
			validity = logins:getValidity(ids)
			self.validity = validity
			if validity[entry.index] > 0 then
				return entry -- valid login
			end
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
	return Wrapper{
		__object = logins,
		ids = ids,
		validity = validity,
		timeupdated = -inf,
		mutex = Mutex(),
		cache = LRU(function(loginId, replacedId, replaced)
			local ok, entry, encodedkey = pcall(logins.getLoginInfo, logins, loginId)
			if not ok then
				if entry._repid ~= logintypes.InvalidLogins then
					error(entry)
				end
				return { id = loginId }
			end
			entry.encodedkey = encodedkey
			entry.pubkey = assert(decodepubkey(encodedkey))
			if replaced == nil then
				entry.index = #ids+1
				log:action(msg.LoginAddedToValidityCache:tag{
					login = loginId,
					entity = entry.entity,
				})
			else
				entry.index = replaced.index
				log:action(msg.LoginReplacedInValidityCache:tag{
					oldlogin = replacedId,
					oldentity = replaced.entity,
					newlogin = loginId,
					newentity = entry.entity,
				})
			end
			ids[entry.index] = loginId
			validity[entry.index] = nil
			return entry
		end),
		getLoginEntry = getLoginEntry,
		getLoginInfo = getLoginInfo,
	}
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
			log:badaccess(msg.AttemptToCallBeforeBusConnection:tag{
				operation = request.operation.name,
			})
		end
	else
		log:access(msg.OutsideBusCall:tag{
			operation = request.operation.name,
		})
	end
end

function Interceptor:receivereply(request)
	local conn = request.connection
	if conn ~= nil and conn.receivereply ~= nil then
		request.connection = nil
		conn:receivereply(request)
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
		log:badaccess(msg.GotCallBeforeBusConnection:tag{
			operation = request.operation.name,
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
		self[field] = orb:narrow(bus:getFacetByName(facetname), typerepid)
	end
	for field, name in pairs(OfferServiceNames) do
		local facetname = assert(offerconst[name.."Facet"], name)
		local typerepid = assert(offertypes[name], name)
		self[field] = orb:narrow(bus:getFacetByName(facetname), typerepid)
	end
	local access = self.AccessControl
	self.busid = access:_get_busid()
	self.buskey = assert(decodepubkey(access:_get_buskey()))
	orb.OpenBusInterceptor:addConnection(self)
	-- create wrapper for core service LoginRegistry
	self.logins = newLoginRegistryWrapper(self.logins)
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
		log:badaccess(msg.AttemptToCallBeforeLogin:tag{
			operation = request.operation.name,
			bus = self.busid,
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
				operation = request.operation.name,
				bus = self.busid,
			})
			localLogout(self)
			if self:onInvalidLogin() then
				request.success = nil -- reissue request to the same reference
				log:badaccess(msg.ReissuingCallAfterCallback:tag{
					operation = request.operation.name,
					bus = self.busid,
				})
				sendBusRequest(self, request)
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
			operation = request.operation.name,
			bus = self.busid,
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
	local id, lease = manager:loginByPassword(entity, pubkey, encrypted)
	self.login = {id=id, entity=entity, pubkey=pubkey}
	self:newrenewer(lease)
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
	local id, lease = attempt:login(pubkey, encrypted)
	self.login = {id=id, entity=entity, pubkey=pubkey}
	self:newrenewer(lease)
end

function Connection:shareLogin(logindata)
	if self:isLoggedIn() then error(msg.ConnectionAlreadyLogged) end
	self.login = decodelogin(logindata)
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



local function createORB(configs)
	local orb = neworb(copy(configs))
	orb.OpenBusInterceptor = Interceptor{ orb = orb }
	orb:setinterceptor(orb.OpenBusInterceptor, "corba")
	return orb
end

local openbus = { createORB = createORB }

openbus.keyname = "my"

function openbus.connectByAddress(host, port, orb)
	local ref = "corbaloc::"..host..":"..port.."/"..BusObjectKey
	if orb == nil then orb = createORB() end
	return Connection{
		orb = orb,
		bus = orb:newproxy(ref, nil, "scs::core::IComponent"),
	}
end



-- insert function argument typing
local argcheck = require "openbus.util.argcheck"
argcheck.convertclass(Connection, {
	--encodeLogin = {},
	loginByPassword = { "string", "string" },
	loginByCertificate = { "string", "userdata" },
	shareLogin = { "string" },
	logout = {},
	getCallerChain = {},
	joinChain = { "nil|table" },
	exitChain = {},
	getJoinedChain = {},
	close = {},
})
argcheck.convertmodule(openbus, {
	createORB = { "nil|table" },
	connectByAddress = { "string", "number", "nil|table" },
})



return openbus
