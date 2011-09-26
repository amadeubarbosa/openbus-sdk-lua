local _G = require "_G"
local ipairs = _G.ipairs
local getmetatable = _G.getmetatable
local newproxy = _G.newproxy
local pcall = _G.pcall
local setmetatable = _G.setmetatable
local rawget = _G.rawget
local rawset = _G.rawset

local table = require "loop.table"
local clear = table.clear
local copy = table.copy

local cothread = require "cothread"
local running = cothread.running
local time = cothread.now

local oil = require "oil"
local neworb = oil.init

local giop = require "oil.corba.giop"
local sysex = giop.SystemExceptionIDs

local log = require "openbus.util.logger"
local oo = require "openbus.util.oo"
local class = oo.class

local msg = require "openbus.core.messages"

local idl = require "openbus.core.idl"
local loadidl = idl.loadto
local LoginInfoSeq = idl.types.services.access_control.LoginInfoSeq

local CredentialContextId = 0x42555300 -- "BUS\0"



local function getCallers(self, contexts)
	local callers
	for _, context in ipairs(contexts) do
		if context.context_id == CredentialContextId then
			local decoder = self.orb:newdecoder(context.context_data)
			return decoder:get(self.credentialType)
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
					callers[1],callers[2] = {id="???",entity=originator},callers[1]
				end
				return callers
			end
		end
	end
end



local function alwaysIndex(default)
	local index = newproxy(true)
	getmetatable(index).__index = function() return default end
	return index
end



local Anybody = alwaysIndex(true)
local Everybody = newproxy(Anybody) -- copy of Anybody
local PredefinedUserSets = {
	none = alwaysIndex(nil),
	any = Anybody,
	all = Everybody,
}



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



local Access = class{
	createORB = createORB,
}

function Access:__init()
	self.callerChainOf = {}
	self.joinedChainOf = {}
	
	do
		local forAllOps = Everybody
		
		function self.newOpAccess(access)
			local default
			return setmetatable(access or {}, {
				__index = function() return default or forAllOps end,
				__newindex = function(self, k, v)
					if k == "*" then
						default = v
					else
						rawset(self, k, v)
					end
				end,
			})
		end
		
		local defOpAccess = setmetatable({}, {
			__index = function() return forAllOps end,
			__newindex = function(self, k, v)
				if k == "*" and v then
					forAllOps = v
				else
					rawset(self, k, v)
				end
			end,
		})
		
		self.grantedUsers = setmetatable({
			["*"] = defOpAccess, -- to get the default
			["IDL:scs/core/IComponent:1.0"] = self.newOpAccess{
				getFacet = Anybody,
				getFacetByName = Anybody,
			},
		}, { __index = function() return defOpAccess end })
	end
	
	local orb = self.orb
	if orb == nil then
		orb = createORB()
		self.orb = orb
	end
	self.credentialType = orb.types:lookup_id(LoginInfoSeq)
	orb:setinterceptor(self, "corba")
end

function Access:setGrantedUsers(interface, operation, users)
	local accessByIface = self.grantedUsers
	local accessByOp = rawget(accessByIface, interface)
	if accessByOp == nil then
		accessByOp = self.newOpAccess()
		accessByIface[interface] = accessByOp
	end
	accessByOp[operation] = PredefinedUserSets[users] or users
end

function Access:getCallerChain()
	return self.callerChainOf[running()]
end

function Access:joinChain(chain)
	local thread = running()
	self.joinedChainOf[thread] = chain or self.callerChainOf[thread]
end

function Access:exitChain()
	self.joinedChainOf[running()] = nil
end

function Access:getJoinedChain()
	return self.joinedChainOf[running()]
end

function Access:shutdown()
	local orb = self.orb
	orb:setinterceptor(nil, "corba")
	clear(self.callerChainOf)
	clear(self.joinedChainOf)
end



local EmptyChain = {}
function Access:sendrequest(request)
	if request.operation_name:find("_", 1, true) ~= 1 then -- not CORBA obj op
		local login = self.login
		if login ~= nil then
			local chain = self.joinedChainOf[running()] or EmptyChain
			local index = #chain+1
			local encoder = self.orb:newencoder()
			chain.n = nil
			chain[index] = login
			encoder:put(chain, self.credentialType)
			chain[index] = nil
			request.service_context = {{
				context_id = CredentialContextId,
				context_data = encoder:getdata(),
			}}
			log:action(msg.InvokeWithCredential:tag{
				operation = request.operation.name,
				login = login.id,
				entity = login.entity,
			})
		else
			log:action(msg.InvokeWithoutCredential:tag{
				operation = request.operation.name,
			})
		end
	end
end

function Access:receiverequest(request)
	if request.servant ~= nil then -- servant object does exist
		local opName = request.operation_name
		if opName:find("_", 1, true) ~= 1 then -- not CORBA obj op
			local ok, callers = pcall(getCallers, self, request.service_context)
			if ok then
				local granted = self.grantedUsers[request.interface.repID][opName]
				if callers ~= nil then
					local last = callers[#callers]
					local login = self.logins:getLoginEntry(last.id)
					if login ~= nil then
						if (granted[login.entity] or granted[callers[1].entity])
						or granted == Anybody
						then
							self.callerChainOf[running()] = callers
							log:action(msg.GrantedCall:tag{
								operation = request.operation.name,
								login = login.id,
								entity = login.entity,
							})
							return
						else
							log:action(msg.DeniedCall:tag{
								operation = request.operation.name,
								login = login.id,
								entity = login.entity,
							})
						end
					else
						log:exception(msg.GotInvalidCaller:tag{
							operation = request.operation.name,
							login = last.id,
							entity = last.entity,
						})
					end
				elseif granted == Anybody then
					log:action(msg.GrantedCallWithoutCallerInfo:tag{
						operation = request.operation.name,
					})
					return
				else
					log:exception(msg.MissingCallerInfo:tag{
						operation = request.operation.name,
					})
				end
				self.callerChainOf[running()] = nil
				request.success = false
				request.results = {self.orb:newexcept{
					"CORBA::NO_PERMISSION",
					minor = 1,
					completed="COMPLETED_NO",
				}}
			else
				request.success = false
				request.results = { callers }
				log:exception(msg.UnableToDecodeCredential:tag{errmsg=callers})
			end
		end
	end
end

function Access:sendreply()
	self.callerChainOf[running()] = nil
end



return Access
