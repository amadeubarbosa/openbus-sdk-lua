-- $Id$

local oil = require "oil"
local oop = require "loop.base"
local log = require "openbus.common.Log"
local LeaseHolder = require "openbus.common.LeaseHolder"

---
--Gerenciador de conexões de membros ao barramento.
---
module("openbus.common.ConnectionManager", oop.class)

---
--Cria o gerenciador de conexões.
--
--@param accessControlServerHost A localização do serviço de controle de acesso.
--@param credentialHolder O objeto onde a credencial do membro fica armazenada.
--
--@return O gerenciador de conexões.
---
function __init(self, accessControlServerHost, credentialHolder)
  local obj = {
    accessControlServerHost = accessControlServerHost,
    credentialHolder = credentialHolder
  }
  return oop.rawnew(self, obj)
end

---
--Obtém referência para o serviço de controle de acesso.
--
--@return O Serviço de Controle de Acesso, ou nil, caso não esteja definido.
--=
function getAccessControlService(self)
  if self.accessControlService == nil then
    local acs = oil.newproxy("corbaloc::"..self.accessControlServerHost.."/ACS",
                             "IDL:openbusidl/acs/IAccessControlService:1.0")
    if acs:_non_existent() then
      log:error("ConnectionManager: Servico de controle de acesso nao encontrado.")
      return nil
    end
    self.accessControlService = acs
  end
  return self.accessControlService
end

---
--Finaliza o procedimento de conexão, após um login bem sucedido salva a
--credencial e inicia o processo de renovação de lease.
--
--@param credential A credencial do membro.
--@param lease O período de tempo entre as renovações do lease.
--@param leaseExpiredCallback Função que será executada quando o lease expirar.
---
function completeConnection(self, credential, lease, leaseExpiredCallback)
  self.credentialHolder:setValue(credential)
  self.leaseHolder = LeaseHolder(
    lease, credential, self.accessControlService, leaseExpiredCallback)
  self.leaseHolder:startRenew()
end

---
--Desconecta um membro do barramento.
---
function disconnect(self)
  if self.leaseHolder then
    self.leaseHolder:stopRenew()
    self.leaseHolder = nil
  end
  if self.accessControlService and self.credentialHolder:hasValue() then
    self.accessControlService:logout(self.credentialHolder:getValue())
    self.credentialHolder:invalidate()
  end
end
