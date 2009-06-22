-- $Id: $

local oil = require "oil"
local oop = require "loop.base"
local log = require "openbus.common.Log"

local tostring = tostring

---
-- API utilitária.
---
module "openbus.util.Utils"

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
  local acs = orb:newproxy("corbaloc::".. host .. ":" .. port .. "/ACS",
                           "IDL:openbusidl/acs/IAccessControlService:1.0")
  if acs:_non_existent() then
    log:error("Utils: Faceta IAccessControlService não encontrada.")
  end
  local lp = orb:newproxy("corbaloc::".. host .. ":" .. port .. "/LP",
                           "IDL:openbusidl/acs/ILeaseProvider:1.0")
  if lp:_non_existent() then
    log:error("Utils: Faceta ILeaseProvider não encontrada.")
  end
  local ic = orb:newproxy("corbaloc::".. host .. ":" .. port .. "/IC",
                           "IDL:scs/core/IComponent:1.0")
  if ic:_non_existent() then
    log:error("Utils: Faceta IComponent não encontrada.")
  end
  return acs, lp, ic
end

