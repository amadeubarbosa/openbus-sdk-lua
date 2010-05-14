-- $Id$

local oop = require "loop.base"

---
--Utilizado para efetuar a autenticação de uma entidade junto ao Serviço de
--Controle de Acesso.
---
module("openbus.authenticators.Authenticator", oop.class)

---
--Autentica uma entidade no barramento.
--
--@param acs O serviço de controle de acesso.
--
--@return A credencial da entidade, ou nil, caso a entidade não tenha permissão
--de acesso.
--@return O tempo pelo qual a credencial é válida (lease).
---
function authenticate(self, acs)
  return nil, -1
end
