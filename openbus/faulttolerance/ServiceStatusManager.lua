local format = string.format
local assert = assert
local loadfile = loadfile
local pairs = pairs
local os = os
local setfenv = setfenv
local tostring = tostring

local Log = require "openbus.util.Log"
local oop = require "loop.simple"

local OilUtilities = require "openbus.util.OilUtilities"
local Utils = require "openbus.util.Utils"

local oil = require "oil"

local orb = oil.orb

module("openbus.faulttolerance.ServiceStatusManager", oop.class)


---
--Cria um gerenciador que atualiza o estado das facetas de uma replica.
--
---
function __init(self)
  if self._keys ~= nil then
    return self
  else
    return oop.rawnew(self, { _keys = self:setReplicas() })
  end
end

---
--Configura as replicas
--
---
function setReplicas(self)
  local DATA_DIR = os.getenv("OPENBUS_DATADIR")
  local configFile = DATA_DIR .."/conf/ACSFaultToleranceConfiguration.lua"
  local loadConfig, err = loadfile(configFile)
  if not loadConfig then
    Log:error(format(
        "O arquivo de configuração %s não pôde ser carregado ou não existe",
        configFile), tostring(err))
    os.exit(1)
  end
  setfenv(loadConfig,_M)
  loadConfig()

  self._keys = {}
  self._keys[Utils.FAULT_TOLERANT_ACS_KEY] = { interface = Utils.FAULT_TOLERANT_SERVICE_INTERFACE,
      hosts = ftconfig.hosts.FTACS, }

  local configFile = DATA_DIR .."/conf/RSFaultToleranceConfiguration.lua"
  local loadConfig, err = loadfile(configFile)
  if not loadConfig then
    Log:error(format(
        "O arquivo de configuração %s não pôde ser carregado ou não existe",
        configFile), tostring(err))
    os.exit(1)
  end
  setfenv(loadConfig,_M)
  loadConfig()

  self._keys[Utils.FAULT_TOLERANT_RS_KEY] = { interface = Utils.FAULT_TOLERANT_SERVICE_INTERFACE,
      hosts = ftconfig.hosts.FTRS, }
end

---
--Atualiza o estado de todas as replicas para um dado objectKey
--
---
function updateStatus(self, interceptedKey)
  local objKey = nil
  if interceptedKey == Utils.ACCESS_CONTROL_SERVICE_KEY or
     interceptedKey == Utils.LEASE_PROVIDER_KEY or
     interceptedKey == Utils.FAULT_TOLERANT_ACS_KEY then
    objKey = Utils.FAULT_TOLERANT_ACS_KEY
  elseif interceptedKey == Utils.REGISTRY_SERVICE_KEY or
         interceptedKey == Utils.FAULT_TOLERANT_RS_KEY then
    objKey = Utils.FAULT_TOLERANT_RS_KEY
  end

  if objKey ~= nil then
    local keyV = self._keys[objKey]
    for _,ref in pairs(keyV.hosts) do
      Log:debug(format("[ServiceStatusManager][updateStatus]Buscando para atualizar replica [%s-TYPE:%s]", ref, keyV.interface))
      local ret, ok, service = oil.pcall(Utils.fetchService, orb, ref, keyV.interface)
      if ret and ok then
        service:updateStatus("all")
        local succ, updated = oil.pcall(service.updateStatus, service, "all")
        if not succ then
          Log:warn("Falha na atualização do estado", updated)
        end
      end
    end
  end
end

