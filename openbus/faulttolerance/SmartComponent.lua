
local pairs     = pairs
local require   = require
local print     = print
local os        = os
local tostring  = tostring
local loadfile  = loadfile
local assert    = assert

local oil = require "oil"
local oop = require "loop.base"
local log = require "openbus.util.Log"
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

  log:faulttolerance("smartpatch configurado.")
  return oop.rawnew(self, { _orb = orb,
                            _keys = keys,
                            _compName = compName,  })
end

function _fetchSmartComponent(self)
  --recarregar timeouts de erro (para tempo ser din�mico em tempo de execu��o)
  local timeOut = assert(loadfile(DATA_DIR .."/conf/FTTimeOutConfiguration.lua"))()

  local services = {}
  local stop = false
  local timeToTry = 0
  --Tempo total em caso de falha = sleep * MAX_TIMES
  local maxTimeToTry = timeOut.fetch.MAX_TIMES
  local ref

  repeat
    for key,values in pairs(self._keys) do
      smartpatch.updateHostInUse(key)
    end

    for key,values in pairs(self._keys) do
      ref = smartpatch.getCurrRef(key)
      local ret, service
      ret, stop, service = oil.pcall(Utils.fetchService, self._orb, ref, values.interface)
      if not ret or not stop then
        services = {}
        os.execute("sleep ".. tostring(timeOut.fetch.sleep))
        break
      else
        services[key] = service
      end
    end

    timeToTry = timeToTry + 1
  until stop or timeToTry == maxTimeToTry

  if services == {} or not stop then
    log:faulttolerance("[_fetchSmartComponent] Componente tolerante a falhas nao encontrado.")
    return false, nil
  end

  for key,values in pairs(self._keys) do
    services[key] = services[key].__smart
  end

  log:faulttolerance("Componente adaptado para ser um smart proxy.")
  return true, services
end


