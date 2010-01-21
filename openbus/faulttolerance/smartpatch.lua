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
	    k = # Components[componentId] + 1
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
		log:faulttolerance("[smartpatch] smartmethod [".. (operation and operation.name or "unknown") .."]")
		local replace = false
		if reply then
			local timeOut = 0
			local timeToWait = 0.5
			local succ = false
			repeat
				succ = reply:ready()
				oil.sleep(timeToWait)
				timeOut = timeOut + timeToWait
			until timeOut == 60 or succ
			   
			local res, ex
			
			if succ then
				res, ex = reply:results()
				if res == false then
				-- ... pega excecao
					ex = CriticalExceptions[ex[1]]
					log:faulttolerance("[smartpatch] operacao retornou com erro no results ")
					replace = true
				else
					-- Segundo o Maia, operation só é 'nil' quando se deu um 'narrow'
					-- no smart proxy, então ao invés de retornar o proxy default
					-- criado pelo 'narrow' original retornamos o smart proxy dele.
					if operation == nil then
						return ex.__smart
					end
				end
			else
				res = false
				ex = "timeout"
				log:faulttolerance("[smartpatch] operacao retornou com erro por timeout")
				replace = true
			end
		end


		if replace then
		--se der erro...
			    local objkey = self.__reference._object
			    log:faulttolerance("[smartpatch] tratando requisicao para key: ".. objkey)
				--pega a lista de replicas com o objectkey do servidor "interceptado"
				local replicas = Replicas[objkey]
	
				-- se nao tiver a lista de replicas retorna com erro
				if replicas == nil then error(ex) end

				local prx2

				repeat
					local numberOfHosts = # Replicas[objkey]

					if indexCurr[objkey] == numberOfHosts then
	   					indexCurr[objkey] = 1
    				else
       					indexCurr[objkey] = indexCurr[objkey] + 1
					end

					-- pega o proxy da proxima replica
					prx2 = orb:newproxy(replicas[indexCurr[objkey]],
					                    self.__type)

					local stop = false                    

					if not prx2:_non_existent() then
						stop = true 
-- Atualiza as réplicas do mesmo componente, como lá de fora o
-- proxy nunca é alterado, não faz sentido, 
-- então o código está comentado
--					    local componentId
--						for compId,v in pairs(Components) do 
--						--buscando o identificador do componente da replica
--								for i,rep in ipairs(v) do 
--									if rep.__reference._object == self.__reference._object then
--									    --encontrou o identificador, salva e sai do for
--										componentId = compId
--										break
--					                end
--								end
--						end
--			
--						for i, rep in ipairs(Components[componentId]) do
--						--para cada replica (faceta) deste componente, atualiza a referencia do proxy
--							local numberOfHosts = # Replicas[rep.__reference._object]
--
--							if indexCurr[rep.__reference._object] == numberOfHosts then
--	   							indexCurr[rep.__reference._object] = 1
--    						else
--       							indexCurr[rep.__reference._object] = indexCurr[rep.__reference._object] + 1
--							end
--							rep = orb:newproxy(replicas[indexCurr[rep.__reference._object]],
--													self.__type)
--							if not rep:_non_existent() then				
--								tabop.copy(rep.__smart, rep)
--							else
--								stop = false
--								break
--							end
--						end
					end					
				until stop

				--troca a referencia do proxy para a nova replica alvo
				tabop.copy(prx2.__smart, self)
				log:faulttolerance("[smartpatch] trocou para replica: " .. 
								replicas[indexCurr[self.__reference._object]])
				--executa o metodo solicitado e retorna
				return self[operation.name](self, ...)
		end

		-- se nao der erro, retorna com os resultados
		return Proxies.assertresults(self, operation,
			Proxies.assertcall(self, operation, reply, ex):results())
	end
end
