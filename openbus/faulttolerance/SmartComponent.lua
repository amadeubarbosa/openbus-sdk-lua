
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
			stop, service = self:fetchService(ref, values.interface)
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

function fetchService(self, objReference, objType)
   
   local success, service = oil.pcall(self._orb.newproxy, self._orb, objReference, objType)

   log:faulttolerance("[fetchService]"..objReference.."-TYPE:"..objType)


   if success then 
		 --TODO: Quando o bug do oil for consertado, mudar para: if not service:_non_existent() then
		 --local succ, non_existent = service.__try:_non_existent()
		 --if succ and not non_existent then
		if OilUtilities:existent(service) then
	 	     --OK
	         log:faulttolerance("[fetchService] Servico encontrado.")
		     --TODO: Essa linha é devido a um outro bug no OiL: type_id = ""
		     service.__reference.type_id = objType
		     -- fim do TODO
		     
		     return true, service
		 end
    end
    log:error("[fetchService]: Faceta ".. objType .." não encontrada.")
    return false, nil

end
