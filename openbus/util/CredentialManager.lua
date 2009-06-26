-- $Id$

local oop = require "loop.base"

---
-- Responsável por armazenar a credencial de um membro. É usado pelo
-- interceptador para obtenção da credencial do membro.
---
module ("openbus.util.CredentialManager", oop.class)

---
--Define a credencial do membro.
--
--@param credential A credencial.
---
function setValue(self, credential)
  self.credentialValue = credential
end

---
--Obtém a credencial do membro.
--
--@return A credencial do membro, que pode ser nula caso ainda não tenha sido
--definida.
---
function getValue(self)
  return self.credentialValue
end

---
--Verifica se a credencial do membro já foi definida.
--
--@return true caso a credencial do membro já tenha sido definida, ou nil em
--caso contrário.
---
function hasValue(self)
  return self.credentialValue ~= nil
end

---
--Remove a credencial do membro. É equivalenete a setValue(nil).
---
function invalidate(self)
  self.credentialValue = nil
end
