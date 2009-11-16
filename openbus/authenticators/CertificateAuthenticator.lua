-- $Id$

local lce = require "lce"

local Authenticator = require "openbus.authenticators.Authenticator"
local log = require "openbus.util.Log"

local oop = require "loop.simple"

---
--Utilizado para efetuar a autentica��o de uma entidade junto ao Servi�o de
--Controle de Acesso atrav�s de chave privada.
---
module("openbus.authenticators.CertificateAuthenticator")

oop.class(_M, Authenticator)

function __init(self, name, privateKeyFile, acsCertificateFile)
  return oop.rawnew(self, {
    name = name,
    privateKeyFile = privateKeyFile,
    acsCertificateFile = acsCertificateFile,
  })
end

---
--@see openbus.authenticators.Authenticator#authenticate
---
function authenticate(self, acs)
  local challenge = acs:getChallenge(self.name)
  if not challenge or #challenge == 0 then
    log:error("OpenBus: o desafio para " .. self.name ..
        " n�o foi obtido junto ao Servico de Controle de Acesso.")
	return nil
  end
  local privateKey, err = lce.key.readprivatefrompemfile(self.privateKeyFile)
  if not privateKey then
    log:error("OpenBus: erro obtendo chave privada para ".. self.name ..
        " em " .. privateKeyFile .. ": " .. err)
    return nil
  end
  challenge = lce.cipher.decrypt(privateKey, challenge)
  local certificate = lce.x509.readfromderfile(self.acsCertificateFile)
  local answer = lce.cipher.encrypt(certificate:getpublickey(), challenge)
  local _, credential, lease = acs:loginByCertificate(self.name, answer)
  return credential, lease
end
