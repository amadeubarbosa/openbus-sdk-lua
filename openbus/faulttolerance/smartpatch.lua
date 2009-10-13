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

local orb

--Lista de replicas para cada objectkey
function setreplicas(objkey, refs)
	Replicas[objkey] = refs
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
			    log:faulttolerance("[smartpatch] tratando requisicao")
				--pega a lista de replicas com o objectkey do servidor "interceptado"
				local replicas = Replicas[self.__reference._object]
				-- se nao tiver a lista de replicas retorna com erro
				if replicas == nil then error(ex) end
				local prx2
				repeat
					-- pega a referencia para a proxima replica da lista
					local nexttobeused = (self.lastused or 0) + 1
					-- se ja tentou todas, sai com erro
					if replicas[nexttobeused] == nil then
						error(ex)
					end
					-- pega o proxy da proxima replica
					prx2 = orb:newproxy(replicas[nexttobeused],
					                    self.__type)
					self.lastused = nexttobeused
				--verifica se nao esta com problema
				until not prx2:_non_existent()

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
