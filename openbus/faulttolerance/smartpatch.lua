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

do
  local ProxyManager = require("oil.builder.typed.client").ProxyManager
  local utils = require "oil.kernel.base.Proxies.utils"
  local assertresults = utils.assertresults
  local unpackrequest = utils.unpackrequest
  local callhandler   = utils.callhandler

  function setorb(value)
    log:faulttolerance("[smartpatch] setorb")
    orb = value
    local SmartProxyManager = ProxyManager{ invoker = smartmethod }
    SmartProxyManager.requester = orb.OperationRequester.requests
    SmartProxyManager.referrer  = orb.ObjectReferrer.references
    SmartProxyManager.servants  = orb.ServantManager.servants
    SmartProxyManager.indexer   = orb.TypeRepository.indexer
    SmartProxyManager.types     = orb.TypeRepository.types

    orb.extraproxies.smart = SmartProxyManager
  end

function smartmethod(invoker, operation)
  return function(self, ...)
    -- realiza a chamada no servidor
    local reply, ex = invoker(self, ...)
    log:faulttolerance("[smartpatch] smartmethod ["..
    (operation and operation.name or "unknown") .."]")
    local replace = false
    --recarregar timeouts de erro (para tempo ser dinâmico em tempo de execução)
    local timeOutConfig = assert(loadfile(DATA_DIR .."/conf/FTTimeOutConfiguration.lua"))()
    local objkey
    if reply ~= nil then
      objkey = reply.object_key
      --Tempo total em caso de falha = sleep * MAX_TIMES
      local timeOut = 0
      local timeToWait = timeOutConfig.reply.sleep
      local replyIsReady
      repeat
        --tempo para esperar uma resposta
        self.__manager.requester:getreply(reply, true)
        replyIsReady = (reply.success ~= nil)
        oil.sleep(timeToWait)
        timeOut = timeOut + 1
      until replyIsReady or (timeOut == timeOutConfig.reply.MAX_TIMES)

      if replyIsReady then
        if reply.success == false then -- obteve uma excecao como resposta
          ex = reply[1]
          log:faulttolerance("[smartpatch] operacao retornou com erro no results: "..ex[1])
          replace = (CriticalExceptions[ex[1]] ~= nil)
        else
          -- Segundo o Maia, operation só é 'nil' quando se deu um 'narrow'
          -- no smart proxy, então ao invés de retornar o proxy default
          -- criado pelo 'narrow' original retornamos o smart proxy dele.
          -- [maia escreveu]: 'operation' nunca pode ser 'nil' no OiL 0.5
          if operation == nil then
            return orb:newproxy(reply[1], "smart")
          end
        end
      else
        log:faulttolerance("[smartpatch] operacao ["..
        (operation and operation.name or "unknown").."] retornou com erro por timeout")
        ex = orb:newexcept{ "CORBA::TIMEOUT" }
        replace = true
      end
    end

    if replace then -- excecao critica ou timeout
      log:faulttolerance("[smartpatch] tratando requisicao para key: ".. objkey)
      --pega a lista de replicas com o objectkey do servidor "interceptado"
      local replicas = Replicas[objkey]

      -- se nao tiver a lista de replicas retorna com erro
      if replicas == nil or #replicas < 2 then
        return callhandler(self, ex, operation)
      end

      --Tempo total em caso de falha = sleep * MAX_TIMES
      local DEFAULT_ATTEMPTS = timeOutConfig.fetch.MAX_TIMES
      local prx2
      local attempts = DEFAULT_ATTEMPTS
      local lastIndex = indexCurr[objkey]
      repeat
        local numberOfHosts = #replicas
        if indexCurr[objkey] == numberOfHosts then
          indexCurr[objkey] = 1
        else
          indexCurr[objkey] = indexCurr[objkey] + 1
        end
        local newIndex = indexCurr[objkey]

        attempts = attempts-1
        --nao pega a mesma replica que deu erro
        if replicas[newIndex] ~= replicas[lastIndex] then
          -- pega o proxy da proxima replica
          log:faulttolerance("[smartpatch] buscando replica: " ..
              replicas[indexCurr[objkey]])
          prx2 = orb:newproxy(replicas[newIndex], "smart")

          if OilUtilities:existent(prx2) then
            log:faulttolerance("[smartpatch] replica encontrada: " ..
                replicas[indexCurr[objkey]])
            break
          end
          prx2 = nil
          oil.sleep(timeOutConfig.fetch.sleep)
        end
      until attempts == 0

      if prx2 then
        --troca a referencia do proxy para a nova replica alvo
        tabop.copy(prx2, self)
        log:faulttolerance("[smartpatch] trocou para replica: " ..
            replicas[indexCurr[objkey]])
        --executa o metodo solicitado e retorna
        return self[operation.name](self, ...)
      else
        log:faulttolerance("[smartpatch] nenhuma replica encontrada apos "
            .. tostring(DEFAULT_ATTEMPTS - attempts) .. " tentativas")
        return callhandler(self, ex, operation)
      end
    end

    -- se nao der erro, retorna com os resultados
    if reply then
      assertresults(self, operation, self.__manager.requester:getreply(reply))
      return assertresults(self, operation, unpackrequest(reply))
    end
    return callhandler(self, ex, operation)
  end
end

end
