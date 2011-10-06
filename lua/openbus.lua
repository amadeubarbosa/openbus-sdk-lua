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
local closeAccess = Access.close
local sendBusRequest = Access.sendrequest
local receiveBusRequest = Access.receiverequest

local cothread = require "cothread"
local schedule = cothread.schedule
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

local function newrenewer(self, lease)
	local manager = self.AccessControl
	local thread
	thread = newthread(function()
		repeat
			log:action(msg.RenewLogin:tag(self.login))
			local ok, result = pcall(manager.renew, manager)
			if ok then
				lease = result
			elseif result._repid == sysex.NO_PERMISSION then
				if self.login ~= nil then
					self.login = nil
					self:onLoginTerminated()
				end
				return
			end
			self.renewer = thread
			deferuntil(time()+lease)
			self.renewer = nil
		until self.login == nil
	end)
	schedule(thread, "defer", lease)
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



local Connection = class({}, Access)

function Connection:__init()
	self.ignoredThreads = {}
	-- setup core access object
	local bus = self.bus
	local orb = self.orb
	-- retrieve core service references
	local ignoredThreads = self.ignoredThreads
	local thread = running()
	ignoredThreads[thread] = true -- perform these calls without credential
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
	ignoredThreads[thread] = nil -- restore only calls with credentials
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


function Connection:sendrequest(request)
	local opName = request.operation_name
	if opName:find("_", 1, true) ~= 1 then -- not CORBA obj op
		if self.login ~= nil or self.ignoredThreads[running()] ~= nil then
			sendBusRequest(self, request)
		else
			request.success = false
			request.results = {self.orb:newexcept{
				_repid = "CORBA::NO_PERMISSION",
				completed = "COMPLETED_NO",
				minor = const.NoLoginCode,
			}}
		end
	end
end

function Connection:receiverequest(request)
	if request.servant ~= nil then -- servant object does exist
		local opName = request.operation_name
		if opName:find("_", 1, true) ~= 1 then -- not CORBA obj op
			receiveBusRequest(self, request)
			local callers = self:getCallerChain()
			if callers ~= nil then
				local login = callers[#callers]
				log:access(msg.GrantedBusCall:tag{
					operation = request.operation.name,
					login = login.id,
					entity = login.entity,
				})
			else
				request.success = false
				request.results = {self.orb:newexcept{
					_repid = "CORBA::NO_PERMISSION",
					completed = "COMPLETED_NO",
					minor = const.InvalidLoginCode,
				}}
				log:access(msg.DeniedCallWithoutCredential:tag{
					operation = request.operation.name,
				})
			end
		end
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
	newrenewer(self, lease)
	return true
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
	newrenewer(self, lease)
	return true
end

function Connection:shareLogin(logindata)
	if self:isLoggedIn() then error(msg.ConnectionAlreadyLogged) end
	self.login = decodelogin(logindata)
end

function Connection:logout()
	local renewer = self.renewer
	if renewer ~= nil then
		unschedule(renewer)
	end
	if self.login ~= nil then
		self.AccessControl:logout()
		self.login = nil
		return true
	end
	return false
end

function Connection:close()
	if self.login ~= nil then
		self:logout()
	end
	closeAccess(self)
end

function Connection:isLoggedIn()
	return self.login ~= nil
end

function Connection:onLoginTerminated()
	-- does nothing by default
end



-- allow login operations to be performed without credentials
for _, loginOpName in ipairs{ "loginByPassword", "loginByCertificate" } do
	local loginOp = Connection[loginOpName]
	Connection[loginOpName] = function(self, ...)
		local ignoredThreads = self.ignoredThreads
		local thread = running()
		ignoredThreads[thread] = true 
		local ok, errmsg = pcall(loginOp, self, ...)
		ignoredThreads[thread] = nil
		if not ok then error(errmsg) end
	end
end



local DenyAll = {}
function DenyAll:sendrequest(request)
	request.success = false
	request.results = {self.orb:newexcept{
		_repid = "CORBA::NO_PERMISSION",
		completed = "COMPLETED_NO",
		minor = const.NoLoginCode,
	}}
	log:access(msg.AttemptToCallBeforeBusConnection:tag{
		operation = request.operation.name,
	})
end
function DenyAll:receiverequest(request)
	request.success = false
	request.results = {self.orb:newexcept{
		_repid = "CORBA::NO_PERMISSION",
		completed = "COMPLETED_NO",
		minor = const.DeniedLoginCode, -- TODO:[maia] is this the right code here?
	}}
	log:access(msg.GotCallBeforeBusConnection:tag{
		operation = request.operation.name,
	})
end


local function connectByComponent(component, orb, log)
	return Connection{
		log = log,
		orb = orb,
		bus = component,
	}
end

local openbus = {
	createORB = neworb,
	connectByComponent = connectByComponent,
}

function openbus.createORB(configs)
	local orb = neworb(configs)
	orb:setinterceptor(DenyAll, "corba")
	return orb
end

function openbus.connectByAddress(host, port, orb, log)
	local ref = "corbaloc::"..host..":"..port.."/"..BusObjectKey
	if orb == nil then orb = neworb() end
	local component = orb:newproxy(ref, nil, "scs::core::IComponent")
	return connectByComponent(component, orb, log)
end

return openbus
