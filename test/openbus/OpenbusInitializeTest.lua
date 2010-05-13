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
local props = nil

oil.verbose:level(5)
Log:level(5)

Suite = {
  Test1 = {
    testInitNullProps = function(self)
      Check.assertTrue(Openbus:init(host, port, nil, iConfig, iConfig))
      Openbus:destroy()
    end,

    testInitNullHost = function(self)
      Check.assertFalse(Openbus:init(nil, port, props, iConfig, iConfig))
    end,

    testInitInvalidPort = function(self)
      Check.assertFalse(Openbus:init(host, -1, props, iConfig, iConfig))
    end,
  },
}
