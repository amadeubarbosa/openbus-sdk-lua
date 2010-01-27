local print = print
local coroutine = coroutine
local Log = require "openbus.util.Log"
local oop = require "loop.simple"


local oil = require "oil"

module ("openbus.util.OilUtilities", oop.class)

function existent(self, proxy)
	local not_exists = nil
	--Tempo total em caso de falha = 0.3 * 10 = 3 segundos
	local threadTime = 0.3
	local succ = false
	local parent = oil.tasks.current

	local thread = coroutine.create(function()
			--TODO: Quando o bug do oil for consertado, mudar para: if not proxy:_non_existent() then
			   --succ, not_exists = proxy.__try:_non_existent()
			   not_exists = proxy:_non_existent()
			   oil.tasks:resume(parent)
	end)

	oil.tasks:resume(thread)
	oil.tasks:suspend(threadTime)
	oil.tasks:remove(thread)

	if not_exists ~= nil then
		--if succ and not not_exists then
		if not not_exists then
			return true
		else
			return false
		end
	else
		return false
	end
end


