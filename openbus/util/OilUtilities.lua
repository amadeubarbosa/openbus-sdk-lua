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
	local timeToTrie = 1
	local threadTime = 0.3
	local executedOK = nil
	local parent = oil.tasks.current

	local thread = coroutine.create(function()
			   executedOK, not_exists = oil.pcall(proxy._non_existent, proxy)
			   oil.tasks:resume(parent)
	end)
	
	while executedOK == nil do
	
	  oil.tasks:resume(thread)
	  oil.tasks:suspend(threadTime)
	  oil.tasks:remove(thread)
	  
	  timeToTrie = timeToTrie + 1
	  
	  if timeToTrie > 10 then
	     break
	  end
    end
    
    if executedOK == nil and not_exists == nil then
        return false   
    elseif not_exists ~= nil then
       if executedOK and not not_exists then		
          return true
       else		
          return false, not_exists
       end
    else
       return false, not_exists
    end
end


