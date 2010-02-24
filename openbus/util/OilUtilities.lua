local print = print
local coroutine = coroutine
local Log = require "openbus.util.Log"
local oop = require "loop.simple"


local oil = require "oil"

module ("openbus.util.OilUtilities", oop.class)

function existent(self, proxy)
    Log:faulttolerance("[existent]OilUtilities")
	local not_exists = nil
	--Tempo total em caso de falha = 0.3 * 10 = 3 segundos
	local threadTime = 0.3
	local succ = false
	local parent = oil.tasks.current

	local thread = coroutine.create(function()
			   succ, not_exists = oil.pcall(proxy._non_existent, proxy)
			   oil.tasks:resume(parent)
	end)

	oil.tasks:resume(thread)
	oil.tasks:suspend(threadTime)
	oil.tasks:remove(thread)

    if not succ and not_exists == nil then
    -- TODO: isso eh um bacalhau
    -- entra nesse if quando chamado em AdaptiveReceptacle, linha 112
    -- "local serviceRec = orb:narrow(conn.objref, "IDL:scs/core/IComponent:1.0")
    --  if not OilUtilities:existent(serviceRec) then"
    --nesse caso, succ veio com o resultado de non_exists e not_exists eh nil
    --porem o Maia falou que isso eh impossivel
    --para ele o pcall retornou com erro e nao retornou a mensagem de erro
    --por outro lado o servico estava vivo e respondeu corretamente
     
        return true
	elseif not_exists ~= nil then
		if succ and not not_exists then		
		--if not not_exists then
			return true
		else		
			return false
		end
	else
		return false
	end
end


