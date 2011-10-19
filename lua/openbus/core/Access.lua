local _G = require "_G"
local ipairs = _G.ipairs
local pcall = _G.pcall

local table = require "loop.table"
local clear = table.clear
local copy = table.copy

local cothread = require "cothread"
local running = cothread.running

local oil = require "oil"
local neworb = oil.init

local log = require "openbus.util.logger"
local oo = require "openbus.util.oo"
local class = oo.class

local msg = require "openbus.core.messages"

local idl = require "openbus.core.idl"
local loadidl = idl.loadto
local const = idl.const.services.access_control
local Identifier = idl.types.Identifier
local LoginInfoSeq = idl.types.services.access_control.LoginInfoSeq

local CredentialContextId = 0x42555300 -- "BUS\0"



local function getCallers(self, contexts)
	for _, context in ipairs(contexts) do
		if context.context_id == CredentialContextId then
			local decoder = self.orb:newdecoder(context.context_data)
			local busid = decoder:get(self.identifierType)
			local callers = decoder:get(self.credentialType)
			callers.busid = busid
			return callers
		end
	end
	if self.legacy then
		for _, context in ipairs(contexts) do
			if context.context_id == 1234 then
				local decoder = self.orb:newdecoder(context.context_data)
				local loginId = decoder:string()
				local entity = decoder:string()
				local originator = decoder:string()
				local callers = {{id=loginId,entity=entity}}
				if originator ~= "" then
					callers[1],callers[2] = {id="unknown",entity=originator},callers[1]
				end
				return callers
			end
		end
	end
end



local function createORB(configs)
	if configs == nil then configs = {} end
	if configs.tcpoptions == nil then
		configs.tcpoptions = {reuseaddr = true}
	end
	configs.flavor = "cooperative;corba.intercepted"
	local orb = neworb(configs)
	loadidl(orb)
	return orb
end


local WeakKeys = {__mode = "k"}

local CallerChainOf = setmetatable({}, WeakKeys)

local Access = class{ createORB = createORB }

function Access:__init()
	self.joinedChainOf = setmetatable({}, WeakKeys)
	local orb = self.orb
	self.identifierType = orb.types:lookup_id(Identifier)
	self.credentialType = orb.types:lookup_id(LoginInfoSeq)
end

function Access:getCallerChain()
	return CallerChainOf[running()]
end

function Access:joinChain(chain)
	local thread = running()
	self.joinedChainOf[thread] = chain or CallerChainOf[thread]
end

function Access:exitChain()
	self.joinedChainOf[running()] = nil
end

function Access:getJoinedChain()
	return self.joinedChainOf[running()]
end



local EmptyChain = {}
function Access:sendrequest(request)
	local login = self.login
	if login ~= nil then
		local encoder = self.orb:newencoder()
		encoder:put(self.busid, self.identifierType)
		local chain = self.joinedChainOf[running()] or EmptyChain
		local index = #chain+1
		chain.n = nil
		chain[index] = login
		encoder:put(chain, self.credentialType)
		chain[index] = nil
		request.service_context = {{
			context_id = CredentialContextId,
			context_data = encoder:getdata(),
		}}
		log:access(msg.BusCall:tag{
			operation = request.operation.name,
			login = login.id,
			entity = login.entity,
			bus = self.busid,
		})
	else
		log:badaccess(msg.CallWithoutCredential:tag{
			operation = request.operation.name,
			bus = self.busid,
		})
	end
end

function Access:receiverequest(request)
	local ok, callers = pcall(getCallers, self, request.service_context)
	if ok then
		if callers ~= nil then
			local last = callers[#callers]
			local login = self.logins:getLoginEntry(last.id)
			if login ~= nil and login.entity == last.entity then
				CallerChainOf[running()] = callers
				log:access(msg.GotBusCall:tag{
					operation = request.operation.name,
					login = login.id,
					entity = login.entity,
					bus = self.busid,
				})
			else
				log:badaccess(msg.GotCallWithInvalidCredential:tag{
					operation = request.operation.name,
					login = last.id,
					entity = last.entity,
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
		request.success = false
		request.results = { callers } -- TODO[maia]: Is a good CORBA SysEx to throw here?
		log:badaccess(msg.UnableToDecodeCredential:tag{errmsg=callers})
	end
end

function Access:sendreply()
	CallerChainOf[running()] = nil
end



return Access
