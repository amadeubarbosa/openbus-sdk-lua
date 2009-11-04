local print = print

local tabop       = require "loop.table"
local ObjectCache = require "loop.collection.ObjectCache"

local oo      = require "oil.oo"
local giop    = require "oil.corba.giop"
local Proxies = require "oil.kernel.base.Proxies"

local log     = require "openbus.util.Log"

module("openbus.faulttolerance.smartpatch", package.seeall)

--Excecoes que serao tratadas
local CriticalExceptions = {}
for _, repid in pairs(giop.SystemExceptionIDs) do
	CriticalExceptions[repid] = true
end

local Replicas = {}
local indexCurr = {}
local Components = {}

local orb

function addSmart(componentId, replica)
	replica = replica.__smart
	if Components[componentId] == nil then
		k = 1
		Components[componentId] = {}
	else
	    k = # Components[componentId] 
	end
	Components[componentId][k] = replica
end

--Lista de replicas para cada objectkey
function setreplicas(objkey, refs)
	Replicas[objkey] = refs
	indexCurr[objkey] = 0
end

function getCurrRef(objkey)
	local replicas = Replicas[objkey]
	for i=1, table.maxn(replicas) do
		if i==indexCurr[objkey] then
    		return tostring(replicas[i])
    	end
	end
	return nil
end

function updateHostInUse(objkey)
    local numberOfHosts = # Replicas[objkey]

	if indexCurr[objkey] == numberOfHosts then
	   indexCurr[objkey] = 1
    else
       indexCurr[objkey] = indexCurr[objkey] + 1
	end
end

function setorb(value)
    log:faulttolerance("[smartpatch] setorb")
	orb = value
	orb.ObjectProxies.extras.__smart = ObjectCache{
		retrieve = function(_, type)
			local class = orb.ObjectProxies.newcache(smartmethod)()
			local updater = {}
			function updater.notify()
				tabop.clear(class)
				class.__context = orb.ObjectProxies.context
				class.__type = type
				oo.initclass(class)
			end
			updater:notify()
			if type.observer then
				rawset(type.observer, class, updater)
			end
			return class
		end
	}
end

function smartmethod(invoker, operation)
	return function(self, ...)
		-- realiza a chamada no servidor
		local reply, ex = invoker(self, ...)
		log:faulttolerance("[smartpatch] smartmethod")
		--se der erro...
		if reply and reply:results() == false then
			-- ... pega excecao
			ex = select(2, reply:results())
			log:faulttolerance("[smartpatch] operacao retornou com erro")
		end

		if ex then
			-- se excecao estiver na lista das excecoes trataveis
			if CriticalExceptions[ex[1]] then
			    local objkey = self.__reference._object
			    log:faulttolerance("[smartpatch] tratando requisicao")
				--pega a lista de replicas com o objectkey do servidor "interceptado"
				local replicas = Replicas[objkey]
				-- se nao tiver a lista de replicas retorna com erro
				if replicas == nil then error(ex) end
				local prx2
				repeat
					self:updateHostInUse(objkey)
					-- pega o proxy da proxima replica
					prx2 = orb:newproxy(replicas[indexCurr[objkey]],
					                    self.__type)
					local stop = false                    
					if not prx2:_non_existent() then
					    local componentId
						for compId,v in pairs(Components) do 
								for i,rep in ipairs(v) do 
									if rep.__reference._object == objKey then
										componentId = compId
										break
					                end
								end
						end
						
						stop = true 
						for i, rep in ipairs(Components[compId]) do
							self:updateHostInUse(rep.__reference._object)
										
							rep = orb:newproxy(replicas[indexCurr[rep.__reference._object]],
													self.__type)
							if not rep:_non_existent() then				
								tabop.copy(rep.__smart, rep)
							else
								stop = false
								break
							end
						end
					end					
					
				--verifica se nao esta com problema
				until stop

				--troca a referencia do proxy para a nova replica
				tabop.copy(prx2.__smart, self)

				--executa o metodo solicitado e retorna
				return self[operation.name](self, ...)
			end
		end

		-- se nao der erro, retorna com os resultados
		return Proxies.assertresults(self, operation,
			Proxies.assertcall(self, operation, reply, ex):results())
	end
end
