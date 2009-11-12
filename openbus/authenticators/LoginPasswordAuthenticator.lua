-- $Id$

local Authenticator = require "openbus.authenticators.Authenticator"

local oop = require "loop.simple"

---
--Utilizado para efetuar a autenticação de uma entidade junto ao Serviço de
--Controle de Acesso através de um login e uma senha.
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
