
local pairs = pairs
local require = require
local print = print

local oil = require "oil"
local oop = require "loop.base"
local log = require "openbus.util.Log"
local OilUtilities = require "openbus.util.OilUtilities"
local smartpatch = require "openbus.faulttolerance.smartpatch"
local Utils = require "openbus.util.Utils"

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

  local status = true
  local services = {}
  local timeToTry = 0
  local stop = false
  local stops = {}
  local maxTimeToTry = 100
  local ref
  
  repeat
  
  		for key,values in pairs(self._keys) do
			smartpatch.updateHostInUse(key)
		end
		
		for key,values in pairs(self._keys) do
			ref = smartpatch.getCurrRef(key)
			ret, stop, service = oil.pcall(Utils.fetchService, self._orb, ref, values.interface)
			if not stop then
				services = {}
				break
			else
				services[key] = service
			end
		end
			
        timeToTry = timeToTry + 1

  --TODO: colocar o timeToTry de acordo com o tempo do monitor da réplica
  until stop or timeToTry == maxTimeToTry

  if services == {} or not stop then
     Log:faulttolerance("[_fetchSmartComponent] Componente tolerante a falhas nao encontrado.")
     return false, nil
  end
  
  for key,values in pairs(self._keys) do
  	  smartpatch.addSmart(self._compName, services[key])
  end

  log:faulttolerance("Componente adaptado para ser um smart proxy.")
  return true, services
  	
end


