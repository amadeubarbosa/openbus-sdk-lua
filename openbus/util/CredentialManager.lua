-- $Id$

local oil = require "oil"
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
  if self.threadCredentialValue and
    self.threadCredentialValue[oil.tasks.current] then
    return self.threadCredentialValue[oil.tasks.current]
  end
  return self.credentialValue
end

---
--Verifica se a credencial do membro já foi definida.
--
--@return true caso a credencial do membro já tenha sido definida, ou nil em
--caso contrário.
---
function hasValue(self)
  if self.threadCredentialValue and
    self.threadCredentialValue[oil.tasks.current] then
    return true
  end
  return self.credentialValue ~= nil
end

---
--Remove a credencial do membro. É equivalenete a setValue(nil).
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
