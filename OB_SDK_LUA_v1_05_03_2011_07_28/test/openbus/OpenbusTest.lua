local oil = require "oil"

local Check = require "latt.Check"

local Openbus = require "openbus.Openbus"
local Utils = require "openbus.util.Utils"
local Log = require "openbus.util.Log"

local iConfig = {
  contextID = 1234,
  credential_type = "IDL:tecgraf/openbus/core/"..Utils.IDL_VERSION..
      "/access_control_service/Credential:1.0",
  credential_type_prev = "IDL:openbusidl/acs/Credential:1.0",
}

local host = "localhost"
local port = 2089
local user = "tester"
local password = "tester"
local oilLogLevel = 0
local sdkLogLevel = 3

-- alterando as propriedades se preciso
local scsutils = require ("scs.core.utils")()
local props = {}
scsutils:readProperties(props, "Test.properties")
scsutils = nil

if props["host.name"] then
  host = props["host.name"].value
end
if props["host.port"] and tonumber(props["host.port"].value) then
  port = tonumber(props["host.port"].value)
end
if props["user"] then
  user = props["user"].value
end
if props["password"] then
  password = props["password"].value
end
if props["oil.verbose"] and tonumber(props["oil.verbose"].value) then
  oilLogLevel = tonumber(props["oil.verbose"].value)
end
if props["openbus.verbose"] and tonumber(props["openbus.verbose"].value) then
  sdkLogLevel = tonumber(props["openbus.verbose"].value)
end

oil.verbose:level(oilLogLevel)
Log:level(sdkLogLevel)

Suite = {
  Test1 = { --Testa o método de inicialização
    testInitNullProps = function(self)
      Check.assertTrue(Openbus:init(host, port, nil, iConfig, iConfig))
      Openbus:destroy()
    end,

    testInitNullHost = function(self)
      Check.assertFalse(Openbus:init(nil, port, props, iConfig, iConfig))
    end,

    testInitNegativePort = function(self)
      Check.assertFalse(Openbus:init(host, -1, props, iConfig, iConfig))
    end,

    testInitInvalidPort = function(self)
      Check.assertFalse(Openbus:init(host, "INVALID", props, iConfig, iConfig))
    end,

    testInitTwice = function(self)
      Check.assertTrue(Openbus:init(host, port, nil, iConfig, iConfig))
      Check.assertFalse(Openbus:init(host, port, nil, iConfig, iConfig))
      Openbus:destroy()
    end,

    testDestroyWithoutInit = function(self)
      Openbus:destroy()
      Check.assertTrue(Openbus:init(host, port, nil, iConfig, iConfig))
      Openbus:destroy()
    end,
  },

  Test2 = {
    beforeEachTest = function(self)
      Openbus:init(host, port, nil, iConfig)
    end,

    afterEachTest = function(self)
      if Openbus:isConnected() then
        Openbus:disconnect()
      end
      Openbus:destroy()
    end,

    testConnectByPassword = function(self)
      Check.assertNotNil(Openbus:connectByLoginPassword(user, password))
      Check.assertTrue(Openbus:disconnect())
    end,

    testConnectByPasswordLoginNull = function(self)
      Check.assertNil(Openbus:connectByLoginPassword(nil, password))
    end,

    testConnectByPasswordInvalidLogin = function(self)
      Check.assertNil(Openbus:connectByLoginPassword("INVALID", password))
    end,

    testConnectByPasswordTwice = function(self)
      Check.assertNotNil(Openbus:connectByLoginPassword(user, password))
      Check.assertNil(Openbus:connectByLoginPassword(user, password))
      Check.assertTrue(Openbus:disconnect())
    end,

    testConnectByCredential = function(self)
      Check.assertNil(Openbus:getCredential())
      Check.assertNotNil(Openbus:connectByLoginPassword(user, password))
      local credential = Openbus:getCredential() 
      Check.assertNotNil(credential)
      Check.assertNotNil(Openbus:connectByCredential(credential))
      Check.assertTrue(Openbus:disconnect())
    end,

    testConnectByCredentialNullCredential = function(self)
      Check.assertNil(Openbus:connectByCredential(nil))
    end,

    testConnectByCredentialInvalidCredential = function(self)
      Check.assertNotNil(Openbus:connectByLoginPassword(user, password))
      local credential = Openbus:getCredential()
      Check.assertNotNil(credential)
      Check.assertTrue(Openbus:disconnect())
      Check.assertNil(Openbus:connectByCredential(credential))
    end,

    testIsConnected = function(self)
      Check.assertFalse(Openbus:isConnected())
      Check.assertNotNil(Openbus:connectByLoginPassword(user, password))
      Check.assertTrue(Openbus:isConnected())
      Check.assertTrue(Openbus:disconnect())
    end,

    testDisconnected = function(self)
      Check.assertFalse(Openbus:disconnect())
    end,

    testGetOrb = function(self)
      Check.assertNotNil(Openbus:getORB())
    end,

    testGetAccessControlService = function(self)
      Check.assertNotNil(Openbus:getORB())
      Check.assertNil(Openbus:getAccessControlService())
      Check.assertNil(Openbus:getRegistryService())
      Check.assertNotNil(Openbus:connectByLoginPassword(user, password))
      Check.assertNotNil(Openbus:getAccessControlService())
      Check.assertTrue(Openbus:disconnect())
    end,

    testGetRegistryService = function(self)
      Check.assertNotNil(Openbus:getORB())
      Check.assertNil(Openbus:getRegistryService())
      Check.assertNotNil(Openbus:connectByLoginPassword(user, password))
      Check.assertNotNil(Openbus:getRegistryService())
      Check.assertTrue(Openbus:disconnect())
    end,

    testCredentialExpired = function(self)
      Check.assertNotNil(Openbus:getORB())
      local lec = {
        wasExpired = false,
        expired = function(self)
          self.wasExpired = true
        end,
        isExpired = function(self)
          return self.wasExpired
        end,
      }
      Log:info("<< Teste da validade da lease >>")

      Check.assertNotNil(Openbus:connectByLoginPassword(user, password))
      Openbus:setLeaseExpiredCallback(lec)
      local acs = Openbus:getAccessControlService()
      Check.assertNotNil(acs)
      acs:logout(Openbus:getCredential())
      while (not (lec:isExpired())) do
        Log:info("Lease não expirou: esperando 30 segundos...")
        oil.sleep(30)
      end
      Check.assertFalse(Openbus:disconnect())
    end,

    testAddLeaseExpiredCbAfterConnect = function(self)
      Check.assertNotNil(Openbus:getORB())
      local lec = {
        wasReconnected = false,
        expired = function(self)
          Check.assertNotNil(Openbus:connectByLoginPassword(user, password))
          self.wasReconnected = true
        end,
        isReconnected = function(self)
          return self.wasReconnected
        end,
      }
      Log:info("<< Teste da reconexão após a lease não ser mais válida [Callback cadastrada depois do connect] >>")
      Check.assertNotNil(Openbus:connectByLoginPassword(user, password))
      Openbus:setLeaseExpiredCallback(lec)
      local acs = Openbus:getAccessControlService()
      Check.assertNotNil(acs)
      acs:logout(Openbus:getCredential())
      while (not (lec:isReconnected())) do
        Log:info("Lease não expirou: esperando 30 segundos...")
        oil.sleep(30)
      end
      Check.assertTrue(Openbus:disconnect())
    end,

    testAddLeaseExpiredCbBeforeConnect = function(self)
      local lec = {
        wasReconnected = false,
        expired = function(self)
          Check.assertNotNil(Openbus:connectByLoginPassword(user, password))
          self.wasReconnected = true
        end,
        isReconnected = function(self)
          return self.wasReconnected
        end,
      }
      Log:info("<< Teste da reconexão após a lease não ser mais válida [Callback cadastrada antes do connect] >>")
      Openbus:setLeaseExpiredCallback(lec)
      Check.assertNotNil(Openbus:connectByLoginPassword(user, password))
      local acs = Openbus:getAccessControlService()
      Check.assertNotNil(acs)
      acs:logout(Openbus:getCredential())
      while (not (lec:isReconnected())) do
        Log:info("Lease não expirou: esperando 30 segundos...")
        oil.sleep(30)
      end
      Check.assertTrue(Openbus:disconnect())
    end,
  },

  Test3 = { -- Testa connectByCertificate
    beforeTestCase = function(self)
      self.systemId     = "TesteBarramento"
      self.deploymentId = self.systemId
      self.testKeyFile  = self.systemId .. ".key"
      self.acsCertFile  = "AccessControlService.crt"
      local testACSCertFile = assert(io.open(self.acsCertFile,"r"))
      testACSCertFile:close()
      Openbus:init(host, port, nil, iConfig)
    end,

    afterTestCase = function(self)
      Openbus:destroy()
    end,

    afterEachTest = function(self)
      if Openbus:isConnected() then
        Openbus:disconnect()
      end
    end,

    testConnectByCertificate = function(self)
      Check.assertNotNil(Openbus:connectByCertificate(self.deploymentId,
          self.testKeyFile, self.acsCertFile))
      Check.assertTrue(Openbus:disconnect())
    end,

    testConnectByCertificateNullKey = function(self)
      Check.assertNil(Openbus:connectByCertificate(self.deploymentId, nil,
          self.acsCertFile))
    end,

    testConnectByCertificateNullACSCertificate = function(self)
      Check.assertNil(Openbus:connectByCertificate(self.deploymentId,
          self.testKeyFile, nil))
    end,

    testConnectByCertificateInvalidEntityName = function(self)
      Check.assertNil(Openbus:connectByCertificate(nil, self.testKeyFile,
          self.acsCertFile))
    end,

    testConnectByCertificateTwice = function(self)
      Check.assertNotNil(Openbus:connectByCertificate(self.deploymentId,
          self.testKeyFile, self.acsCertFile))
      Check.assertNil(Openbus:connectByCertificate(self.deploymentId,
          self.testKeyFile, self.acsCertFile))
      Check.assertTrue(Openbus:disconnect())
    end,
  },
}
