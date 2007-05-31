-----------------------------------------------------------------------------
-- Gerenciador de conex�es de membros ao barramento
--
-- �ltima altera��o:
--   $Id$
-----------------------------------------------------------------------------
local oop = require "loop.base"
local log = require "openbus.common.Log"
local LeaseHolder = require "openbus.common.LeaseHolder"
local print = print

module("openbus.common.ConnectionManager", oop.class)

function __init(self, obj)
 return oop.rawnew(self, obj)
end

--
-- Finaliza o procedimento de conex�o, ap�s um login bem sucedido
--  salva a credencial e inicia o processo de renova��o de lease
--
function completeConnection(self, credential, lease)
  self.credentialHolder:setValue(credential)
  self.leaseHolder = LeaseHolder(lease, credential, self.accessControlService)
  self.leaseHolder:startRenew()
end

--
-- Desconecta um membro do barramento
--
function disconnect(self)
  self.leaseHolder:stopRenew()
  self.accessControlService:logout(self.credentialHolder:getValue())
  self.credentialHolder:invalidate()
end
