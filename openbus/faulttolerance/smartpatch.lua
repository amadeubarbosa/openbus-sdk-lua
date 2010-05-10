local os          = os
local print       = print
local tostring    = tostring
local loadfile    = loadfile
local assert      = assert
local tabop       = require "loop.table"
local ObjectCache = require "loop.collection.ObjectCache"

local oo      = require "oil.oo"
local giop    = require "oil.corba.giop"
local Proxies = require "oil.kernel.base.Proxies"

local log          = require "openbus.util.Log"
local OilUtilities = require "openbus.util.OilUtilities"

local DATA_DIR = os.getenv("OPENBUS_DATADIR")

module("openbus.faulttolerance.smartpatch", package.seeall)

--Excecoes que serao tratadas
local CriticalExceptions = {}
for _, repid in pairs(giop.SystemExceptionIDs) do
  if repid == "IDL:omg.org/CORBA/NO_RESPONSE:1.0" or
    repid == "IDL:omg.org/CORBA/COMM_FAILURE:1.0" or
    repid == "IDL:omg.org/CORBA/OBJECT_NOT_EXIST:1.0" or
    repid == "IDL:omg.org/CORBA/TRANSIENT:1.0" or
    repid == "IDL:omg.org/CORBA/TIMEOUT:1.0" or
    repid == "IDL:omg.org/CORBA/NO_RESOURCES:1.0" or
    repid == "IDL:omg.org/CORBA/FREE_MEM:1.0" or
    repid == "IDL:omg.org/CORBA/NO_MEMORY:1.0" or
    repid == "IDL:omg.org/CORBA/INTERNAL:1.0" then
    CriticalExceptions[repid] = true
  else
    CriticalExceptions[repid] = false
  end
end

local Replicas = {}
local indexCurr = {}
local Components = {}

local orb

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
    log:faulttolerance("[smartpatch] smartmethod ["..
        (operation and operation.name or "unknown") .."]")
    local replace = false
    local timeOutConfig
    if reply then
      --recarregar timeouts de erro (para tempo ser dinâmico em tempo de execução)
      timeOutConfig = assert(loadfile(DATA_DIR .."/conf/FTTimeOutConfiguration.lua"))()
      --Tempo total em caso de falha = sleep * MAX_TIMES
      local timeOut = 0
      local timeToWait = timeOutConfig.reply.sleep
      local succ = false
      repeat
        --tempo para esperar uma resposta
        succ = reply:ready()
        oil.sleep(timeToWait)
        timeOut = timeOut + 1
      until timeOut == timeOutConfig.reply.MAX_TIMES or succ

      local res, ex2

      if succ then
        res, ex2 = reply:results()
        if res == false then
        -- ... pega excecao
          log:faulttolerance("[smartpatch] operacao retornou com erro no results: " .. ex2[1])
          if CriticalExceptions[ex2[1]] then
            replace = true
          end
        else
          -- Segundo o Maia, operation só é 'nil' quando se deu um 'narrow'
          -- no smart proxy, então ao invés de retornar o proxy default
          -- criado pelo 'narrow' original retornamos o smart proxy dele.
          if operation == nil then
            return ex2.__smart
          end
        end
      else
        res = false
        ex2 = "timeout"
        log:faulttolerance("[smartpatch] operacao retornou com erro por timeout")
        replace = true
      end
    end

    if replace then
      --se der erro...
      if not timeOut then
        --recarregar timeouts de erro (para tempo ser dinâmico em tempo de execução)
        local timeOutConfig = assert(loadfile(DATA_DIR .."/conf/FTTimeOutConfiguration.lua"))()
      end
      --Tempo total em caso de falha = sleep * MAX_TIMES
      local DEFAULT_ATTEMPTS = timeOutConfig.fetch.MAX_TIMES

      local objkey = self.__reference._object
      log:faulttolerance("[smartpatch] tratando requisicao para key: ".. objkey)
      --pega a lista de replicas com o objectkey do servidor "interceptado"
      local replicas = Replicas[objkey]

      -- se nao tiver a lista de replicas retorna com erro
      if replicas == nil or #replicas < 2 then error(ex) end

      local prx2
      local attempts = DEFAULT_ATTEMPTS
      local stop = false
      local lastIndex = indexCurr[objkey]
      repeat
        local numberOfHosts = # Replicas[objkey]
        if indexCurr[objkey] == numberOfHosts then
          indexCurr[objkey] = 1
        else
          indexCurr[objkey] = indexCurr[objkey] + 1
        end

        --nao pega a mesma replica que deu erro
        if replicas[indexCurr[objkey]] ~= replicas[lastIndex] then
          -- pega o proxy da proxima replica
          log:faulttolerance("[smartpatch] buscando replica: " ..
              replicas[indexCurr[self.__reference._object]])
          prx2 = orb:newproxy(replicas[indexCurr[objkey]], self.__type)

          --if not prx2:_non_existent() then
          if OilUtilities:existent(prx2) then
            --OK
            stop = true
            log:faulttolerance("[smartpatch] replica encontrada: " ..
                replicas[indexCurr[self.__reference._object]])
          else
            prx2 = nil
            oil.sleep(timeOutConfig.fetch.sleep)
          end
        end
        attempts = attempts - 1
      until stop or attempts == 0

      if prx2 then
        --troca a referencia do proxy para a nova replica alvo
        tabop.copy(prx2.__smart, self)
        log:faulttolerance("[smartpatch] trocou para replica: " ..
            replicas[indexCurr[self.__reference._object]])
        --executa o metodo solicitado e retorna
        return self[operation.name](self, ...)
      else
        log:faulttolerance("[smartpatch] nenhuma replica encontrada apos "
            .. tostring(DEFAULT_ATTEMPTS - attempts) .. " tentativas")
      end
    end

    -- se nao der erro, retorna com os resultados
    return Proxies.assertresults(self, operation,
        Proxies.assertcall(self, operation, reply, ex):results())
  end
end
