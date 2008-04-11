-- $Id$

local log = require "openbus.common.Log"
local oop = require "loop.simple"
local lce = require "lce"

local ConnectionManager = require "openbus.common.ConnectionManager"

---
--Gerenciador de conex�es e desconex�es de servi�os ao barramento (autenticados
--por certificado).
---
module "openbus.common.ServiceConnectionManager"

oop.class(_M, ConnectionManager)

---
--Cria o gerenciador de conex�es.
--
--@param accessControlServerHost A localiza��o do servi�o de controle de acesso.
--@param credentialManager O objeto onde a credencial do membro fica armazenada.
--@param privateKeyFile O caminho para o arquivo da chave privada do servi�o.
--@param certificateFile O caminho para o arquivo do certificado do servi�o.
--
--@return O gerenciador de conex�es.
---
function __init(self, accessControlServerHost, credentialManager, privateKeyFile, certificateFile)
  local obj = 
    ConnectionManager.__init(self, accessControlServerHost, credentialManager)
  obj.privateKeyFile = privateKeyFile 
  obj.certificateFile = certificateFile
  return obj
end

---
--Conecta o servi�o ao barramento com autentica��o via certificado.
--
--@param name O nome do servi�o.
--@param leaseExpiredCallback Fun��o que ser� executada quando o lease expirar.
--
--@return true caso o servi�o tenha sido conectado, ou false caso contr�rio.
---
function connect(self, name, leaseExpiredCallback)
  self.name = name
  self.leaseExpiredCallback = leaseExpiredCallback
  local accessControlService = self:getAccessControlService()
  if accessControlService == nil then
    return false
  end
  local challenge = accessControlService:getChallenge(name)
  if not challenge then
    log:error("ServiceConnectionManager: o desafio para "..name..
              " n�o foi obtido junto ao Servico de Controle de Acesso.")
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

  local certificate = lce.x509.readfromderfile(self.certificateFile)
  answer = lce.cipher.encrypt(certificate:getpublickey(), answer)

  local success, credential, lease =
    accessControlService:loginByCertificate(name, answer)
  if not success then
    log:error("ServiceConnectionManager: insucesso no login de "..name)
    return false
  end
  self:completeConnection(credential, lease,
    function() self.reconnect(self) end)
  return true
end

---
--Reconecta o cliente ap�s uma expira��o de lease.
---
function reconnect(self)
  log:conn("ServiceConnectionManager: reconectando "..self.name)
  if self:connect(self.name, self.leaseExpiredCallback) then
    log:conn("ServiceConnectionManager: "..self.name.." reconectado")
    if self.leaseExpiredCallback then
      self.leaseExpiredCallback()
    end
  else
    log:error("ServiceConnectionManager: insucesso na reconex�o de "..self.name)
  end
end
