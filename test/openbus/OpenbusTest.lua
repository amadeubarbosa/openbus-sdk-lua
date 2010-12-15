local oil = require "oil"

local Check = require "latt.Check"

local Openbus = require "openbus.Openbus"
local Utils = require "openbus.util.Utils"
local Log = require "openbus.util.Log"

local iConfig = {
  contextID = 1234,
  credential_type = "IDL:tecgraf/openbus/core/"..Utils.OB_VERSION..
      "/access_control_service/Credential:1.0",
  credential_type_prev = "IDL:tecgraf/openbus/core/"..Utils.OB_PREV..
      "/access_control_service/Credential:1.0",
}

local host = "localhost"
local port = 2089
local props = {}

local user = "tester"
local password = "tester"

local entityName = "TesteBarramento"
local privateKey = "resources/Teste.key"
local acsCertificate = "resources/AccessControlService.crt"

oil.verbose:level(5)
Log:level(5)

Suite = {
  Test1 = {
    beforeTestCase = function(self)
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

    testConnectByPassword = function(self)
      Check.assertTrue(Openbus:connectByLoginPassword(user, password))
      Check.assertTrue(Openbus:disconnect())
    end,

    testConnectByPasswordLoginNull = function(self)
      Check.assertFalse(Openbus:connectByLoginPassword(nil, password))
    end,

    testConnectByPasswordInvalidLogin = function(self)
      Check.assertFalse(Openbus:connectByLoginPassword("INVALID", password))
    end,

    testConnectByPasswordTwice = function(self)
      Check.assertTrue(Openbus:connectByLoginPassword(user, password))
      Check.assertFalse(Openbus:connectByLoginPassword(user, password))
      Check.assertTrue(Openbus:disconnect())
    end,

    testConnectByCertificate = function(self)
      Check.assertTrue(Openbus:connectByCertificate(entityName, privateKey, acsCertificate))
      Check.assertTrue(Openbus:disconnect())
    end,
    
    testConnectByCertificateNullKey = function(self)
      Check.assertFalse(Openbus:connectByCertificate(entityName, nil, acsCertificate))
    end,
    
    testConnectByCertificateNullACSCertificate = function(self)
      Check.assertFalse(Openbus:connectByCertificate(entityName, privateKey, nil))
    end,

    testConnectByCertificateInvalidEntityName = function(self)
      Check.assertFalse(Openbus:connectByCertificate(nil, privateKey, acsCertificate))
    end,

    testConnectByCertificateTwice = function(self)
      Check.assertTrue(Openbus:connectByCertificate(entityName, privateKey,
          acsCertificate))
      Check.assertFalse(Openbus:connectByCertificate(entityName, privateKey,
          acsCertificate))
      Check.assertTrue(Openbus:disconnect())
    end,

    testConnectByCredential = function(self)
      Check.assertNil(Openbus:getCredential())
      Check.assertTrue(Openbus:connectByLoginPassword(user, password))
      local credential = Openbus:getCredential();
      Check.assertNotNil(credential)
      Check.assertFalse(Openbus:connect(credential))
      Check.assertTrue(Openbus:disconnect())      
    end,

    testConnectByCredentialNullCredential = function(self)
      Check.assertFalse(Openbus:connectByCredential(nil))
    end,

    testConnectByCredentialInvalidCredential = function(self)
      Check.assertTrue(Openbus:connectByLoginPassword(user, password))
      local credential = Openbus:getCredential();
      Check.assertNotNil(credential)
      Check.assertTrue(Openbus:disconnect())      
      Check.assertFalse(Openbus:connectByCredential(credential))
    end,

    testIsConnected = function(self)
      Check.assertFalse(Openbus:isConnected())
      Check.assertTrue(Openbus:connectByLoginPassword(user, password))
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
      Check.assertFalse(Openbus:getAccessControlService())
      Check.assertFalse(Openbus:getRegistryService())
      Check.assertTrue(Openbus:connectByLoginPassword(user, password))
      Check.assertNotNil(Openbus:getAccessControlService())
      Check.assertTrue(Openbus:disconnect())
    end,

    testGetRegistryService = function(self)
      Check.assertFalse(Openbus:getRegistryService())
      Check.assertTrue(Openbus:connectByLoginPassword(user, password))
      Check.assertNotNil(Openbus:getRegistryService())
      Check.assertTrue(Openbus:disconnect())
    end,

    testCredentialExpired = function(self)
      local lec = {
        wasExpired = false,
        expired = function(self)
          self.wasExpired = true
        end,
        isExpired = function(self)
          return self.wasExpired
        end,
      }
    
      Check.assertTrue(Openbus:connectByLoginPassword(user, password))
      Openbus:setLeaseExpiredCallback(lec)
      local acs = Openbus:getAccessControlService()
      Check.assertNotNil(acs)
      acs:logout(Openbus:getCredential())
      while (not (lec:isExpired())) do
        oil.sleep(30)
      end
      Check.assertFalse(Openbus:disconnect())      
    end,

    testAddLeaseExpiredCbBeforeConnect = function(self)
      local lec = {
        wasReconnected = false,
        expired = function(self)
          Check.assertTrue(Openbus:connectByLoginPassword(user, password))
          self.wasReconnected = true
        end,
        isReconnected = function(self)
          return self.wasReconnected
        end,
      }

      Check.assertTrue(Openbus:connectByLoginPassword(user, password))
      Openbus:setLeaseExpiredCallback(lec)
      local acs = Openbus:getAccessControlService()
      Check.assertNotNil(acs)
      acs:logout(Openbus:getCredential())
      while (not (lec:isReconnected())) do
        oil.sleep(30)
      end
      Check.assertTrue(Openbus:disconnect())      
    end,

    testAddLeaseExpiredCbAfterConnect = function(self)
      local lec = {
        wasReconnected = false,
        expired = function(self)
          Check.assertTrue(Openbus:connectByLoginPassword(user, password))
          self.wasReconnected = true
        end,
        isReconnected = function(self)
          return self.wasReconnected
        end,
      }

      Openbus:setLeaseExpiredCallback(lec)
      Check.assertTrue(Openbus:connectByLoginPassword(user, password))
      local acs = Openbus:getAccessControlService()
      Check.assertNotNil(acs)
      acs:logout(Openbus:getCredential())
      while (not (lec:isReconnected())) do
        oil.sleep(30)
      end
      Check.assertTrue(Openbus:disconnect())      
    end,
  },
}
