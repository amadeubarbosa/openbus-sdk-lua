-- $Id$

local oop = require "loop.base"

---
-- Respons�vel por armazenar a credencial de um membro. � usado pelo
-- interceptador para obten��o da credencial do membro.
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
--Obt�m a credencial do membro.
--
--@return A credencial do membro, que pode ser nula caso ainda n�o tenha sido
--definida.
---
function getValue(self)
  return self.credentialValue
end

---
--Verifica se a credencial do membro j� foi definida.
--
--@return true caso a credencial do membro j� tenha sido definida, ou nil em
--caso contr�rio.
---
function hasValue(self)
  return self.credentialValue ~= nil
end

---
--Remove a credencial do membro. � equivalenete a setValue(nil).
---
function invalidate(self)
  self.credentialValue = nil
end
