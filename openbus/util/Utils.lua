-- $Id: $

local type = type
local ipairs = ipairs
local print = print
local tostring = tostring
local assert = assert
local os = os
local string = string
local table  = table
local unpack = unpack

local oil = require "oil"
local oop = require "loop.base"
local log = require "openbus.util.Log"
local OilUtilities = require "openbus.util.OilUtilities"


---
-- API utilitária.
---
module "openbus.util.Utils"

---
--  A interface IAccessControlService.
---
ACCESS_CONTROL_SERVICE_INTERFACE =
  "IDL:openbusidl/acs/IAccessControlService:1.0"

---
--  A interface ILeaseProvider.
---
LEASE_PROVIDER_INTERFACE = "IDL:openbusidl/acs/ILeaseProvider:1.0"

---
--  A interface IFaultTolerantService.
---
FAULT_TOLERANT_SERVICE_INTERFACE = 
  "IDL:openbusidl/ft/IFaultTolerantService:1.0"

---
--  As chaves CORBALOC para obtenção das interfaces do ACS.
---
ICOMPONENT_KEY = "/IC"
ACCESS_CONTROL_SERVICE_KEY = "/ACS"
LEASE_PROVIDER_KEY = "/LP"
FAULT_TOLERANT_ACS_KEY = "/FTACS"
REGISTRY_SERVICE_KEY = "/RS"
FAULT_TOLERANT_RS_KEY = "/FTRS"

---
--  A interface ISessionService.
---
SESSION_SERVICE_INTERFACE = "IDL:openbusidl/ss/ISessionService:1.0"

---
--  O nome da faceta do Serviço de Sessão.
---
SESSION_SERVICE_FACET_NAME = "sessionService"

---
--  A interface IHDataService.
---
DATA_SERVICE_INTERFACE = "IDL:openbusidl/data_service/IHDataService:1.0"

---
--  Nome da propriedade que indica o identificador de um componente.
---
COMPONENT_ID_PROPERTY_NAME = "component_id"

---
-- Obtém referências para as principais facetas do Serviço de Controle de
-- Acesso.
--
-- @param orb O ORB a ser utilizado para obter as facetas.
-- @param host String com o host do Serviço de Controle de Acesso
-- @param port Número ou string com a porta do Serviço de Controle de Acesso
--
-- @return A faceta IAccessControlService, ou nil, caso não seja encontrada.
-- @return A faceta ILeaseProvider, ou nil, caso não seja encontrada.
-- @return A faceta IComponent, ou nil, caso não seja encontrada.
--
function fetchAccessControlService(orb, host, port)
  port = tostring(port)
  local acs = orb:newproxy("corbaloc::".. host .. ":" .. port ..
    ACCESS_CONTROL_SERVICE_KEY, "IDL:openbusidl/acs/IAccessControlService:1.0")
  if acs:_non_existent() then
    log:error("Utils: Faceta IAccessControlService não encontrada.")
  end
  local lp = orb:newproxy("corbaloc::".. host .. ":" .. port ..
    LEASE_PROVIDER_KEY, "IDL:openbusidl/acs/ILeaseProvider:1.0")
  if lp:_non_existent() then
    log:error("Utils: Faceta ILeaseProvider não encontrada.")
  end
  local ic = orb:newproxy("corbaloc::".. host .. ":" .. port .. ICOMPONENT_KEY,
    "IDL:scs/core/IComponent:1.0")
  if ic:_non_existent() then
    log:error("Utils: Faceta IComponent não encontrada.")
  end
  local ft = orb:newproxy("corbaloc::".. host .. ":" .. port .. FAULT_TOLERANT_ACS_KEY,
    "IDL:openbusidl/ft/IFaultTolerantService:1.0")
  if ft:_non_existent() then
    log:error("Utils: Faceta IFaultTolerantService não encontrada.")
  end
  return acs, lp, ic, ft
end


patt="%-?%-?(%w+)(=?)(.*)"
-- Parsing arguments and returns a 'table[option]=value'
function parse_args(arg, usage_msg, allowempty)
	assert(type(arg)=="table","ERROR: Missing arguments! This program should be loaded from console.")
	local arguments = {}
	-- concatenates with the custom usage_msg
	usage_msg=[[
 Usage: ]]..arg[0]..[[ OPTIONS
 Valid OPTIONS:
]] ..usage_msg

	if not (arg[1]) and not allowempty then print(usage_msg) ; os.exit(1) end

	for i,param in ipairs(arg) do
		local opt,_,value = param:match(patt)
		if opt == "h" or opt == "help" then
			print(usage_msg)
			os.exit(1)
		end
		if opt and value then
			if arguments[opt] then
				arguments[opt] = arguments[opt].." "..value
			else
				arguments[opt] = value
			end
		end
	end

	return arguments
end




