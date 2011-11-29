local _G = require "_G"
local assert = _G.assert
local error = _G.error
local ipairs = _G.ipairs
local next = _G.next
local pairs = _G.pairs
local rawget = _G.rawget
local tostring = _G.tostring

local coroutine = require "coroutine"
local newthread = coroutine.create
local running = coroutine.running

local lce = require "lce"
local encrypt = lce.cipher.encrypt
local decrypt = lce.cipher.decrypt
local readcertificate = lce.x509.readfromderstring

local table = require "loop.table"
local copy = table.copy
local memoize = table.memoize

local BiCyclicSets = require "loop.collection.BiCyclicSets"
local Wrapper = require "loop.object.Wrapper"

local Mutex = require "cothread.Mutex"

local giop = require "oil.corba.giop"
local sysex = giop.SystemExceptionIDs

local log = require "openbus.util.logger"
local msg = require "openbus.util.messages"
local oo = require "openbus.util.oo"
local class = oo.class

local idl = require "openbus.core.idl"
local loginconst = idl.const.services.access_control
local logintypes = idl.types.services.access_control
local offerconst = idl.const.services.offer_registry
local offertypes = idl.types.services.offer_registry
local BusObjectKey = idl.const.BusObjectKey
local Access = require "openbus.core.Access"
local neworb = Access.createORB
local sendBusRequest = Access.sendrequest
local receiveBusRequest = Access.receiverequest

local cothread = require "cothread"
local resume = cothread.next
local unschedule = cothread.unschedule
local deferuntil = cothread.defer
local time = cothread.now
local threadtrap = cothread.trap



local function getpublickey(certificate)
	local result, errmsg = readcertificate(certificate)
	if result then
		result, errmsg = result:getpublickey()
		if result then
			return result
		end
	end
	return nil, msg.UnableToReadPublicKey:tag{ errmsg = errmsg }
end

local function getEntryFromCache(self, loginId)
	local usage = self.usage
	local ids = self.ids
	local validity = self.validity
	local id2entry = self.id2entry
	local leastused = self.leastused
	local logins = self.__object
	-- add crendential to cache if it is not there
	local entry = id2entry[loginId]
	if entry == nil then
		local ok
		ok, entry = pcall(logins.getLoginInfo, logins, loginId)
		if not ok then
			if entry._repid ~= logintypes.InvalidLogins then
				error(entry)
			end
			entry = { id = loginId }
		end
		local size = #ids
		if size < self.maxcachesize then
			size = size+1
			entry.index = size
			ids[size] = loginId
			usage:add(entry, leastused)
			leastused = entry
			log:action(msg.LoginAddedToValidityCache:tag{
				login = entry.id,
				entity = entry.entity,
			})
		else
			log:action(msg.LoginReplacedInValidityCache:tag{
				oldlogin = leastused.id,
				oldentity = leastused.entity,
				newlogin = loginId,
				newentity = entry.entity,
			})
			id2entry[leastused.id] = nil
			validity[leastused.index] = nil
			leastused.id = loginId
			leastused.entity = entry.entity
			entry = leastused
		end
		id2entry[loginId] = entry
	end
	-- update login usage in the cache
	if entry == leastused then
		self.leastused = usage:predecessor(entry)
	else
		usage:move(entry, leastused)
	end
	-- use information in the cache to validate the login
	local time2live = self.validity[entry.index]
	if time2live == 0 then
		log:action(msg.InvalidLoginInValidityCache:tag{
			login = loginId,
			entity = entry.entity,
		})
	elseif time2live ~= nil and time2live > time()-self.timeupdated then
		log:action(msg.ValidLoginInValidityCache:tag{
			login = loginId,
			entity = entry.entity,
		})
		return entry -- valid login in cache
	else -- update validity cache
		log:action(msg.UpdateLoginValidityCache:tag{count=#ids})
		self.timeupdated = time()
		local validity = logins:getValidity(ids)
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
	throw.InvalidLogins{loginsId={id}}
end

local function localLogout(self)
	self.login = nil
	local renewer = self.renewer
	if renewer ~= nil then
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
	end
end

function Interceptor:receivereply(request)
	local conn = self.connection
	if conn ~= nil and conn.receivereply ~= nil then
		request.connection = nil
		conn:receivereply(request)
	end
end

function Interceptor:receiverequest(request)
	if self.ignoredThreads[running()] == nil then
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
end

function Interceptor:sendreply(request)
	local conn = request.connection
	if conn ~= nil and conn.sendreply ~= nil then
		request.connection = nil
		conn:sendreply(request)
	end
end



local Connection = class({}, Access)

function Connection:__init()
	-- retrieve core service references
	local bus = self.bus
	local orb = self.orb
	local iceptor = orb.OpenBusInterceptor
	local ignored = iceptor.ignoredThreads
	local thread = running()
	ignored[thread] = true -- perform these calls without credential
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
	self.busid = self.AccessControl:_get_busid()
	iceptor:addConnection(self)
	ignored[thread] = nil -- restore only calls with credentials
	-- create wrapper for core service LoginRegistry
	self.logins = Wrapper{
		connection = self,
		__object = self.logins,
		maxcachesize = 128,
		timeupdated = 0,
		usage = BiCyclicSets(),
		ids = {},
		validity = {},
		id2entry = {},
		mutex = Mutex(),
		getLoginEntry = getLoginEntry,
		getLoginInfo = getLoginInfo,
	}
end

function Connection:newrenewer(lease)
	local manager = self.AccessControl
	local thread
	thread = newthread(function()
		while self.login ~= nil do
			self.renewer = thread
			deferuntil(time()+lease)
			self.renewer = nil
			log:action(msg.RenewLogin:tag(self.login))
			local ok, result = pcall(manager.renew, manager)
			if ok then
				lease = result
			elseif result._repid == sysex.NO_PERMISSION then
				self.login = nil -- flag connection is logged out
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
				sendBusRequest(self, request)
				log:badaccess(msg.ReissuingCallAfterCallback:tag{
					operation = request.operation.name,
					bus = self.busid,
				})
			end
		end
	end
end

function Connection:receiverequest(request)
	receiveBusRequest(self, request)
	local callers = self:getCallerChain()
	if callers == nil then
		request.success = false
		request.results = {self.orb:newexcept{
			"CORBA::NO_PERMISSION",
			completed = "COMPLETED_NO",
			minor = loginconst.InvalidLoginCode,
		}}
	end
end


function Connection:loginByPassword(entity, password)
	if self:isLoggedIn() then error(msg.ConnectionAlreadyLogged) end
	local manager = self.AccessControl
	local buskey = assert(getpublickey(manager:_get_certificate()))
	local encoded, errmsg = encrypt(buskey, password)
	if encoded == nil then
		error(msg.CorruptedBusCertificate:tag{
			certificate = buscert,
			errmsg = errmsg,
		})
	end
	local lease
	self.login, lease = manager:loginByPassword(entity, encoded)
	self:newrenewer(lease)
end

function Connection:loginByCertificate(entity, privatekey)
	if self:isLoggedIn() then error(msg.ConnectionAlreadyLogged) end
	local manager = self.AccessControl
	local buskey = assert(getpublickey(manager:_get_certificate()))
	local attempt, challenge = manager:startLoginByCertificate(entity)
	local secret, errmsg = decrypt(privatekey, challenge)
	if secret == nil then
		attempt:cancel()
		error(msg.CorruptedPrivateKey:tag{
			privatekey = privatekey,
			errmsg = errmsg,
		})
	end
	local answer, errmsg = encrypt(buskey, secret)
	if answer == nil then
		attempt:cancel()
		error(msg.CorruptedBusCertificate:tag{
			certificate = buscert,
			errmsg = errmsg,
		})
	end
	local lease
	self.login, lease = attempt:login(answer)
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
	loginByCertificate = { "string", "table" },
	shareLogin = { "string" },
	logout = {},
	getCallerChain = {},
	joinChain = { "table" },
	exitChain = {},
	getJoinedChain = {},
	close = {},
})
argcheck.convertmodule(openbus, {
	createORB = { "nil|table" },
	connectByAddress = { "string", "number", "nil|table" },
})



return openbus
