-- $Id$

local oop = require "loop.base"

---
--Utilizado para efetuar a autentica��o de uma entidade junto ao Servi�o de
--Controle de Acesso.
---
module("openbus.authenticators.Authenticator", oop.class)

---
--Autentica uma entidade no barramento.
--
--@param acs O servi�o de controle de acesso.
--
--@return A credencial da entidade, ou nil, caso a entidade n�o tenha permiss�o
--de acesso.
--@return O tempo pelo qual a credencial � v�lida (lease).
---
function authenticate(self, acs)
  return nil, -1
end
