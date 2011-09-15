local _G = require "_G"
local pairs = _G.pairs
local setmetatable = _G.setmetatable

local coroutine = require "coroutine"
local newthread = coroutine.create

local table = require "loop.table"
local copy = table.copy

local cothread = require "cothread"
local running = cothread.running

local oo = require "openbus.util.oo"
local class = oo.class

local log = require "openbus.util.logger"
local msg = require "openbus.util.messages"

local baseAPI = require "openbus"



local WeakKeyMeta = { __mode = "k" }

local AccessOf = setmetatable({}, WeakKeyMeta) -- [thread]=access

local MultiplexedAccess = class()

local MultiplexerOf = memoize(function(orb)
	return MultiplexedAccess{ orb = orb }
end)

function MultiplexedAccess:__init()
	self.accesses = {}
end

function MultiplexedAccess:addAccess(access)
	local accesses = self.multiplexer.accesses
	accesses[access] = true
	local backup = access.shutdown
	function access.shutdown(...)
		accesses[access] = nil
		if next(accesses) == nil then
			local orb = self.orb
			MultiplexerOf[orb] = nil
			orb:setinterceptor(nil, "corba")
		end
		return backup(...)
	end
end

function MultiplexedAccess:sendrequest(...)
	local access = AccessOf[running()]
	if access ~= nil then
		access:sendrequest(...)
	end
end

function MultiplexedAccess:receiverequest(...)
	for access in pairs(self.accesses) do
		if access.validator:isValid(credential) then
			AccessOf[running()] = access
			access:receiverequest(...)
			break
		end
	end
end

function MultiplexedAccess:sendreply(...)
	local thread = running()
	local access = AccessOf[thread]
	if access ~= nil then
		access:sendreply(...)
		AccessOf[thread] = nil
	end
end



local function multiplexedConnect(orb, connect, ...)
	if orb ~= nil then
		local access = orb:getinterceptor("corba")
		if access ~= nil then
			local multiplexer = MultiplexerOf[orb]
			if access ~= multiplexer then
				multiplexer:addAccess(access)
			end
			local conn = connect(...) -- this sets the ORB's interceptor
			multiplexer:addAccess(conn.access)
			orb:setinterceptor(multiplexer, "corba") -- restore interceptor
			return conn
		end
	end
	return connect(...)
end



local OpenBus = class({}, baseAPI.OpenBus)

local connectByPassword = OpenBus.connectByPassword
function OpenBus:connectByPassword(entity, password)
	local orb = self.orb
	return multiplexedConnect(orb, connectByPassword, self,
	                          entity, password)
end

local connectByCertificate = OpenBus.connectByCertificate
function OpenBus:connectByCertificate(entity, privatekey)
	local orb = self.orb
	return multiplexedConnect(orb, connectByCertificate, self,
	                          entity, privatekey)
end

local connectBySharedLogin = OpenBus.connectBySharedLogin
function OpenBus:connectBySharedLogin(logindata, bus, orb)
	local orb = self.orb
	return multiplexedConnect(orb, connectBySharedLogin, self, logindata)
end



local openbus = copy(baseAPI, { OpenBus = OpenBus })

function openbus.getThreadCallerChain()
	local access = AccessOf[running()]
	if access ~= nil then
		return access:getCallerChain()
	end
end

function openbus.setThreadConnection(access)
	AccessOf[running()] = access
end

function openbus.getThreadConnection()
	return AccessOf[running()]
end

return openbus
