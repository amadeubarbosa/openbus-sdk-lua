-- $Id$

local oil = require "oil"
local oop = require "loop.base"
local log = require "openbus.common.Log"
local LeaseRenewer = require "openbus.common.LeaseRenewer"

---
--Gerenciador de conex�es de membros ao barramento.
---
module("openbus.common.ConnectionManager", oop.class)

---
--Cria o gerenciador de conex�es.
--
--@param accessControlServerHost A localiza��o do servi�o de controle de acesso.
--@param credentialManager O objeto onde a credencial do membro fica armazenada.
--
--@return O gerenciador de conex�es.
---
function __init(self, accessControlServerHost, credentialManager)
  local obj = {
    accessControlServerHost = accessControlServerHost,
    credentialManager = credentialManager
  }
  return oop.rawnew(self, obj)
end

---
--Obt�m refer�ncia para o servi�o de controle de acesso.
--
--@return O Servi�o de Controle de Acesso, ou nil, caso n�o esteja definido.
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
--Finaliza o procedimento de conex�o, ap�s um login bem sucedido salva a
--credencial e inicia o processo de renova��o de lease.
--
--@param credential A credencial do membro.
--@param lease O per�odo de tempo entre as renova��es do lease.
--@param leaseExpiredCallback Fun��o que ser� executada quando o lease expirar.
---
function completeConnection(self, credential, lease, leaseExpiredCallback)
  self.credentialManager:setValue(credential)
  self.leaseRenewer = LeaseRenewer(
    lease, credential, self.accessControlService, leaseExpiredCallback)
  self.leaseRenewer:startRenew()
end

---
--Desconecta um membro do barramento.
---
function disconnect(self)
  if self.leaseRenewer then
    self.leaseRenewer:stopRenew()
    self.leaseRenewer = nil
  end
  if self.accessControlService and self.credentialManager:hasValue() then
    self.accessControlService:logout(self.credentialManager:getValue())
    self.credentialManager:invalidate()
  end
end
