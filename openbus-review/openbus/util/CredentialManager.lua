-- $Id$

local oil = require "oil"
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
  if self.threadCredentialValue and
    self.threadCredentialValue[oil.tasks.current] then
    return self.threadCredentialValue[oil.tasks.current]
  end
  return self.credentialValue
end

---
--Verifica se a credencial do membro j� foi definida.
--
--@return true caso a credencial do membro j� tenha sido definida, ou nil em
--caso contr�rio.
---
function hasValue(self)
  if self.threadCredentialValue and
    self.threadCredentialValue[oil.tasks.current] then
    return true
  end
  return self.credentialValue ~= nil
end

---
--Remove a credencial do membro. � equivalenete a setValue(nil).
---
function invalidate(self)
  self.credentialValue = nil
end

---
--Define a credencial da thread atual.
--
--@param credential A credencial.
---
function setThreadValue(self, credential)
  if not self.threadCredentialValue then
    self.threadCredentialValue = {}
  end
  self.threadCredentialValue[oil.tasks.current] = credential
end

---
--Fornece a credencial da thread atual.
---
function getThreadValue(self)
  if self.threadCredentialValue then
    return self.threadCredentialValue[oil.tasks.current]
  end
  return nil
end

---
--Remove a credencial da thread atual.
---
function invalidateThreadValue(self)
  if self.threadCredentialValue then
    self.threadCredentialValue[oil.tasks.current] = nil
  end
end
