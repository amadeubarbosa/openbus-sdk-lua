local oil = require "oil"

local Check = require "latt.Check"

local Openbus = require "openbus.Openbus"
local Utils = require "openbus.util.Utils"
local Log = require "openbus.util.Log"

local iConfig = {
  contextID = 1234,
  credential_type_v1_05 = "IDL:tecgraf/openbus/core/v"..Utils.OB_VERSION.."/access_control_service/Credential:1.0",
  credential_type = "IDL:openbusidl/acs/Credential:1.0"
}

local host = "localhost"
local port = 2089
local user = "tester"
local password = "tester"
local oilLogLevel = 0
local sdkLogLevel = 3

local entityName = "TesteBarramento_v152"
local privateKey = "resources/TesteBarramento_v152.key"
local acsCertificate = "AccessControlService.crt"

-- alterando as propriedades se preciso
local scsutils = require ("scs.core.utils").Utils()
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
