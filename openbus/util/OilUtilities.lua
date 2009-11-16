local print = print
local coroutine = coroutine
local Log = require "openbus.util.Log"
local oop = require "loop.simple"


local oil = require "oil"
local orb = oil.orb

module ("openbus.util.OilUtilities", oop.class)

function existent(self, proxy)

	local succ = false
	local not_exists = nil

	local parent = oil.tasks.current

	local thread = coroutine.create(function()
		--TODO: Quando o bug do oil for consertado, mudar para: if not proxy:_non_existent() then
--oil.verbose:print("proxy", proxy.__reference)
	       succ, not_exists = proxy.__try:_non_existent()
	       oil.tasks:resume(parent)
	end)

	oil.tasks:resume(thread)
	oil.tasks:suspend(5)
	oil.tasks:remove(thread)

	if not_exists ~= nil then
	    Log:warn("Ele existe ?", not not_exists)
		if succ and not not_exists then
			return true
		else
			return false
		end
	else
	    Log:warn("Deu timeout")
		return false
	end
end


