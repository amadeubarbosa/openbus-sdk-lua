-----------------------------------------------------------------------------
-- Gerenciador de conexões e desconexões de serviços ao barramento
-- (autenticados por certificado)
-- 
-- Última alteração:
--   $Id$
-----------------------------------------------------------------------------
local log = require "openbus.common.Log"
local oop = require "loop.simple"
local lce = require "lce"

local ConnectionManager = require "openbus.common.ConnectionManager"

module("openbus.common.ServiceConnectionManager", oop.class, ConnectionManager)

function __init(self, accessControlService, credentialHolder, 
                privateKeyFile, certificateFile)
  local obj = { accessControlService = accessControlService, 
                credentialHolder = credentialHolder,
                privateKeyFile = privateKeyFile, 
                certificateFile = certificateFile }
  ConnectionManager:__init(obj)
  return oop.rawnew(self, obj)
end

--
-- Conecta o serviço ao barramento com autenticação via certificado
--
function connect(self, name)
  local challenge = self.accessControlService:getChallenge(name)
  if not challenge then
    log:error("ServiceConnectionManager: o desafio para "..name..
              " não foi obtido junto ao Servico de Controle de Acesso.")
    return false
  end
  local privateKey, errorMessage = 
    lce.key.readprivatefrompemfile(self.privateKeyFile)
  if not privateKey then
    log:error("ServiceConnectionManager: erro obtendo chave privada para "..
              name.." em "..  self.privateKeyFile..": "..errorMessage)
    return false
  end
  local answer = lce.cipher.decrypt(privateKey, challenge)
  privateKey:release()

  local certificate = lce.x509.readfromderfile(self.certificateFile)
  answer = lce.cipher.encrypt(certificate:getpublickey(), answer)
  certificate:release()

  local success, credential, lease =
    self.accessControlService:loginByCertificate(name, answer)
  if not success then
    log:error("ServiceConnectionManager: insucesso no login de "..name)
    return false
  end
  self:completeConnection(credential, lease)
  return true
end
