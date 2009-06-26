-- $Id: $

local oil = require "oil"
local oop = require "loop.base"
local log = require "openbus.util.Log"

local tostring = tostring

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
--  As chaves CORBALOC para obtenção das interfaces do ACS.
---
ICOMPONENT_KEY = "/IC"
ACCESS_CONTROL_SERVICE_KEY = "/ACS"
LEASE_PROVIDER_KEY = "/LP"

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
  return acs, lp, ic
end

