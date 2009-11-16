
local assert = assert
local print = print
local loadfile = loadfile
local pairs = pairs
local os = os

local Log = require "openbus.util.Log"
local oop = require "loop.simple"

local OilUtilities = require "openbus.util.OilUtilities"
local Utils = require "openbus.util.Utils"

local oil = require "oil"

local orb = oil.orb

module("openbus.faulttolerance.ServiceStatusManager", oop.class)


---
--Cria um gerenciador que atualiza o estado das replica.
--
---
function __init(self)

  if self._keys ~= nil then
     Log:faulttolerance("ServiceStatusManager constructer - return EXISTENT")
     return self
  else
    Log:faulttolerance("FTManager constructer - return NEW instance")
    return oop.rawnew(self, { _keys = self:setReplicas() })
  end
end

---
--Configura as replicas
--
---
function setReplicas(self)
    	local DATA_DIR = os.getenv("OPENBUS_DATADIR")
    	local ftconfig = assert(loadfile(DATA_DIR .."/conf/ACSFaultToleranceConfiguration.lua"))()

		self._keys = {}
    	self._keys[Utils.FAULT_TOLERANT_ACS_KEY] = { interface = Utils.FAULT_TOLERANT_SERVICE_INTERFACE,
    									  		  hosts = ftconfig.hosts.FTACS, }
    									  		  
   		ftconfig = assert(loadfile(DATA_DIR .."/conf/RSFaultToleranceConfiguration.lua"))()

    	self._keys[Utils.FAULT_TOLERANT_RS_KEY] = { interface = Utils.FAULT_TOLERANT_SERVICE_INTERFACE,
    									  		  hosts = ftconfig.hosts.FTRS, }
    									  		  
end

---
--Atualiza o estado de todas as replicas para um dado objectKey
--
---
function updateStatus(self, interceptedKey)
    interceptedKey = "/" .. interceptedKey  
	local objKey = nil
	if interceptedKey == Utils.ACCESS_CONTROL_SERVICE_KEY or
	   interceptedKey == Utils.LEASE_PROVIDER_KEY or
	   interceptedKey == Utils.FAULT_TOLERANT_ACS_KEY then
	   objKey = Utils.FAULT_TOLERANT_ACS_KEY
	else
		if interceptedKey == Utils.REGISTRY_SERVICE_KEY or
		   interceptedKey == Utils.FAULT_TOLERANT_RS_KEY then
		   objKey = Utils.FAULT_TOLERANT_RS_KEY
		end 
	end	 

	if objKey ~= nil then
		local keyV = self._keys[objKey]
		for _,ref in pairs(keyV.hosts) do
			Log:faulttolerance("Buscando para atualizar replica [" .. ref .."]")
			local ret, ok, service = oil.pcall(Utils.fetchService, orb, ref, keyV.interface)
			if ok then
				service:updateStatus()
			end
		end
	end
end







