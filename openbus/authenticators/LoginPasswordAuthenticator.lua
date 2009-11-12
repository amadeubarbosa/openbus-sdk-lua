-- $Id$

local Authenticator = require "openbus.authenticators.Authenticator"

local oop = require "loop.simple"

---
--Utilizado para efetuar a autentica��o de uma entidade junto ao Servi�o de
--Controle de Acesso atrav�s de um login e uma senha.
---
module("openbus.authenticators.LoginPasswordAuthenticator")

oop.class(_M, Authenticator)

function __init(self, name, password)
  return oop.rawnew(self, {
	  name = name,
	  password = password,
  })
end

---
--@see openbus.authenticators.Authenticator#authenticate
---
function authenticate(self, acs)
  local _, credential, lease = acs:loginByPassword(self.name, self.password)
  return credential, lease
end
