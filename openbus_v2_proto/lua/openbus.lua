local _G = require "_G"
local assert = _G.assert
local ipairs = _G.ipairs
local next = _G.next
local pairs = _G.pairs
local rawget = _G.rawget
local tostring = _G.tostring

local coroutine = require "coroutine"
local newthread = coroutine.create

local lce = require "lce"
local encrypt = lce.cipher.encrypt
local decrypt = lce.cipher.decrypt
local readcertificate = lce.x509.readfromderstring

local table = require "loop.table"
local memoize = table.memoize

local BiCyclicSets = require "loop.collection.BiCyclicSets"

local cothread = require "cothread"
local schedule = cothread.schedule
local unschedule = cothread.unschedule
local deferuntil = cothread.defer
local time = cothread.now
local threadtrap = cothread.trap

local Mutex = require "cothread.Mutex"

local log = require "openbus.util.logger"
local msg = require "openbus.util.messages"

local oo = require "openbus.util.oo"
local class = oo.class

local idl = require "openbus.core.idl"
local types = idl.types.services.access_control
local const = idl.values.services.access_control

local Access = require "openbus.core.Access"



local function getpublickey(certificate)
	local result, errmsg = readcertificate(path)
	if result then
		result, errmsg = result:getpublickey()
		if result then
			return result
		end
	end
	return nil, msg.UnableToReadPublicKey:tag{ path = path, errmsg = errmsg }
end



local function getEntryFromCache(self, loginId)
	local usage = self.usage
	local ids = self.ids
	local validity = self.validity
	local id2entry = self.id2entry
	local leastused = self.leastused
	local logins = self.logins
	-- add crendential to cache if it is not there
	local entry = id2entry[loginId]
	if entry == nil then
		local ok
		ok, entry = pcall(logins.getLoginInfo, logins, loginId)
		if not ok then
			if entry[1] ~= types.InvalidLogins then
				error(entry)
			end
			entry = { id = loginId }
		end
		local size = #ids
		if size < self.maxsize then
			size = size+1
			entry.index = size
			ids[size] = entry
			usage:add(entry, leastused)
			leastused = entry
			log:action(msg.LoginAddedToValidityCache:tag{
				login = login.id,
				entity = login.entity,
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
		self.leastused = usage:previous(entry)
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
		local validity = logins:getLoginValidity(ids)
		self.validity = validity
		if validity[entry.index] > 0 then
			return entry -- valid login
		end
	end
end



local CachedValiditor = class{
	maxsize = 128,
	timeupdated = 0,
}

function CachedValiditor:__init()
	self.usage = BiCyclicSets()
	self.ids = {}
	self.validity = {}
	self.id2entry = {}
	self.mutex = Mutex()
end

function CachedValiditor:getLoginEntry(loginId)
	local mutex = self.mutex
	repeat until mutex:try() -- get exclusive access to this cache
	local ok, entity = pcall(getEntryFromCache, self, loginId)
	mutex:free() -- release exclusive access so other threads can access
	assert(ok, entity)
	return entity
end



local function getFacet(cmp, facet, type)
	local obj = cmp:getFacetByName(facet)
	if obj ~= nil then
		return obj:__narrow(type)
	end
end



local Connection = class({}, Access)

function Connection:__init()
	-- setup core access object
	local bus = self.bus
	self.orb = bus.orb
	self.validator = CachedValiditor{
		logins = getFacet(bus.component,
		                  const.LoginRegistryFacet,
		                  types.LoginRegistry),
	}
	-- create renewer thread
	local renewer = newthread(function()
		local manager = self.manager
		repeat
			log:action(msg.RenewCredential:tag{???})
			local leasetime = manager:renew()
			self.renewersuspended = true
			deferuntil(time()+leasetime)
			self.renewersuspended = false
		until self.renewer == nil
	end)
	threadtrap[renewer] = function()
		self.renewer = nil
		self:shutdown()
	end
	schedule(renewer, "defer", self.lease)
	self.renewer = renewer
end

function Connection:disconnect()
	local renewer = self.renewer
	if renewer ~= nil then
		if self.renewersuspended then unschedule(renewer) end
		self.renewer = nil
	end
	self.manager:logout()
	self:shutdown()
end

function Connection:isConnected()
	return self.renewer ~= nil
end

function Connection:onNoPermission()
	-- does nothing by default
end



local OpenBus = class()

function OpenBus:connectByPassword(entity, password)
	local manager = getFacet(self.component,
	                         const.LoginManagerFacet,
	                         types.LoginManager)
	local login, lease = manager:loginByPassword(entity, password)
	return Connection{
		bus = self,
		lease = lease,
		login = login,
		manager = manager,
	}
end

function OpenBus:connectByCertificate(entity, privatekey)
	local manager = getFacet(self.component,
	                         const.LoginManagerFacet,
	                         types.LoginManager)
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
	local login, lease = attempt:login(answer)
	return Connection{
		bus = self,
		lease = lease,
		login = login,
		manager = manager,
	}
end

function OpenBus:connectBySharedLogin(logindata)
	local logins = getFacet(self.component,
	                        const.LoginRegistryFacet,
	                        types.LoginRegistry)
	local login = decodelogin(logindata)
	local lease = logins:getLoginValitidy({login.id})[1]
	if lease == 0 then
		error(msg.InvalidLogin:tag{
			login = login.id,
			entity = login.entity,
		})
	end
	return Connection{
		bus = self,
		lease = lease,
		login = login,
		manager = getFacet(self.component,
		                   const.LoginManagerFacet,
		                   types.LoginManager)
	}
end



local function initORB(configs)
	if configs == nil then configs = {} end
	if configs.tcpoptions == nil then
		configs.tcpoptions = {reuseaddr = true}
	end
	configs.flavor = "cooperative;corba.intercepted"
	local orb = neworb(configs)
	loadidl(orb)
	return orb
end

local function getBusByComponent(component, orb)
	return OpenBus{
		orb = orb,
		component = component,
	}
end

local openbus = {
	OpenBus = OpenBus,
	initORB = initORB,
	getBusByComponent = getBusByComponent,
}

function openbus.getBusByAddress(host, port, orb)
	if orb == nil then orb = initORB() end
	local ref = "corbaloc::"..host..":"..port.."/"..idl.values.BusObjectKey
	local component = orb:newproxy(ref, nil, "scs::core::IComponent")
	return getBusByComponent(component, orb)
end

return openbus
