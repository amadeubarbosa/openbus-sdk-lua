local format = string.format
local pairs     = pairs
local require   = require
local os        = os
local tostring  = tostring
local loadfile  = loadfile
local assert    = assert

local oil = require "oil"
local oop = require "loop.base"
local Log = require "openbus.util.Log"
local OilUtilities = require "openbus.util.OilUtilities"
local smartpatch = require "openbus.faulttolerance.smartpatch"
local Utils = require "openbus.util.Utils"

local DATA_DIR = os.getenv("OPENBUS_DATADIR")

---
-- Representa um componente smart
---
module("openbus.faulttolerance.SmartComponent", oop.class)


function __init(self, orb, compName, keys)
  smartpatch.setorb(orb)

    for key,values in pairs(keys) do
      smartpatch.setreplicas(key, values.hosts)
    end

  return oop.rawnew(self, { _orb = orb,
                            _keys = keys,
                            _compName = compName,  })
end

function _fetchSmartComponent(self)
  --recarregar timeouts de erro (para tempo ser dinâmico em tempo de execução)
  local timeOut = assert(loadfile(DATA_DIR .."/conf/FTTimeOutConfiguration.lua"))()

  local services = {}
  local stop = false
  local timeToTry = 0
  --Tempo total em caso de falha = sleep * MAX_TIMES
  local maxTimeToTry = timeOut.fetch.MAX_TIMES
  local ref

  repeat
    Log:debug(format("Tentativa %d de obter as réplicas do componente %s",
        timeToTry, self._compName))
    for key,values in pairs(self._keys) do
      smartpatch.updateHostInUse(key)
    end

    for key,values in pairs(self._keys) do
      ref = smartpatch.getCurrRef(key)
      Log:debug(format("Obtendo a faceta %s do componente %s", ref,
          self._compName))
      local ret, service
      ret, stop, service = oil.pcall(Utils.fetchService, self._orb, ref, values.interface)
      if not ret or not stop then
        services = {}
        Log:warn(format("A faceta %s não foi encontrada. Aguardando %d segundos",
            ref, timeOut.fetch.sleep))
        oil.sleep(timeOut.fetch.sleep)
        break
      else
        services[key] = service
      end
    end

    timeToTry = timeToTry + 1

  until stop or timeToTry == maxTimeToTry

  --TODO: corrigir esse teste abaixo do "services == {}" que nunca sera igual pois "{}" e uma nova 
  if services == {} or not stop then
    Log:error(format("O componente %s tolerante à falhas não foi encontrado",
        self._compName))
    return false, nil
  end

  for key,values in pairs(self._keys) do
    services[key] = self._orb:newproxy(services[key], "smart")
  end

  Log:debug(format("O componente %s foi adaptado para ser um smart proxy",
      self._compName))
  return true, services
end


