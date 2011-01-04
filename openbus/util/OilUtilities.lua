local print = print
local coroutine = coroutine
local loadfile = loadfile
local assert = assert
local oop = require "loop.simple"

local oil = require "oil"

local DATA_DIR = os.getenv("OPENBUS_DATADIR")

module ("openbus.util.OilUtilities", oop.class)

function existent(self, proxy)

  --recarregar timeouts de erro (para tempo ser dinâmico em tempo de execução)
  local timeOut = assert(loadfile(DATA_DIR .."/conf/FTTimeOutConfiguration.lua"))()

  --Tempo total em caso de falha = sleep * MAX_TIMES
  local MAX_TIMES = timeOut.non_existent.MAX_TIMES
  local timeToTrie = 1
  local threadTime = timeOut.non_existent.sleep
  local parent = oil.tasks.current
  local executedOK, not_exists = nil, nil
  local thread = coroutine.create(function()
        executedOK, not_exists = oil.pcall(proxy._non_existent, proxy)
        oil.tasks:resume(parent)
  end)

  oil.tasks:resume(thread)
  if executedOK == nil then
    oil.tasks:suspend(threadTime*MAX_TIMES)
    if executedOK == nil then
      oil.tasks:remove(thread)
      return false, "call timeout"
    end
  end
  if executedOK and not not_exists then
    return true, true
  else
    return false, not_exists
  end
end


