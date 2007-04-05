--
-- Objeto que armazena a credencial de um membro
--
local oop = require "loop.base"

module ("openbus.common.CredentialHolder", oop.class)

function setValue(self, credential)
  self.credentialValue = credential
end

function getValue(self)
  return self.credentialValue
end

function hasValue(self)
  return self.credentialValue ~= nil
end

function invalidate(self)
  self.credentialValue = nil
end
