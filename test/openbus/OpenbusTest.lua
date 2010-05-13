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
local props = {}

local user = "tester"
local password = "tester"

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

    testConnectByCertificate = function(self)
    end,

    testConnectByCertificateNullKey = function(self)
      Check.assertFalse(Openbus:connectByCertificate("name", nil, nil))
    end,

    testConnectByCertificateNullACSCertificate = function(self)
      Check.assertFalse(Openbus:connectByCertificate("name", nil, nil))
    end,

    testConnectByCredential = function(self)
    end,

    testConnectByCredentialNullCredential = function(self)
      Check.assertFalse(Openbus:connectByCredential(nil))
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
      -- Check.assertNotNil(Openbus:getRegistryService())
      Check.assertTrue(Openbus:disconnect())
    end,

    testCredentialExpired = function(self)
      local wasExpired = false
      local lec = {
        wasExpired = false,

        expired = function(self)
          self.wasExpired = true
        end,

        getWasExpired = function(self)
          return self.wasExpired
        end,
      }

      Check.assertTrue(Openbus:connectByLoginPassword(user, password))
      Openbus:setLeaseExpiredCallback(lec)
      while (not (lec:getWasExpired())) do
        print("A")
        oil.sleep(30)
      end
      Check.assertTrue(Openbus:disconnect())
    end,

    testAddLeaseExpiredCbBeforeConnect = function(self)
    end,

    testAddLeaseExpiredCbAfterConnect = function(self)
    end,
  },
}
