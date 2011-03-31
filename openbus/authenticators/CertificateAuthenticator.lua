-- $Id$

local format = string.format
local tostring = tostring

local lce = require "lce"

local Authenticator = require "openbus.authenticators.Authenticator"
local Log = require "openbus.util.Log"

local oop = require "loop.simple"

---
--Utilizado para efetuar a autenticação de uma entidade junto ao Serviço de
--Controle de Acesso através de chave privada.
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
    Log:error(format("Não foi possível obter um desafio para a entidade %s",
        self.name))
  return nil
  end
  local privateKey, err = lce.key.readprivatefrompemfile(self.privateKeyFile)
  if not privateKey then
    Log:error(format(
        "Ocorreu um erro ao carregar o arquivo de chave privada %s: %s",
        self.privateKeyFile, tostring(err)))
    return nil
  end
  challenge, err = lce.cipher.decrypt(privateKey, challenge)
  if not challenge then
    Log:error(format("Ocorreu um erro ao descriptografar o desafio obtido: %s",
        tostring(err)))
  end
  local certificate, err = lce.x509.readfromderfile(self.acsCertificateFile)
  if not certificate then
    Log:error(format("Ocorreu um erro ao carregar o arquivo de certificado digital do barramento %s",
        self.acsCertificateFile), tostring(err))
  end
  local answer = lce.cipher.encrypt(certificate:getpublickey(), challenge)
  local succ, credential, lease = acs:loginByCertificate(self.name, answer)
  if succ then
    Log:debug(format("O login da entidade %s foi realizado com sucesso",
        self.name))
    return credential, lease
  end
  return nil, -1
end
