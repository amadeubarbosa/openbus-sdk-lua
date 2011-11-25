local _G = require "_G"
local os = _G.os
local io = _G.io
local pairs = _G.pairs
local string = _G.string
local assert = _G.assert
local tonumber = _G.tonumber
local tostring = _G.tostring

local socket = require "socket.core"
local oil = require "oil"
local lce = require "lce"
local Check = require "latt.Check"

local Openbus = require "openbus"
local Log = require "openbus.util.logger"

local orb = oil.init {flavor = "cooperative;corba.intercepted",}

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

local busadmin = "busadmin --host="..host.." --port="..port..
    " --login="..user.." --password=".. password
local logoutput = " 2>>management-err.txt >>management.txt "


Suite = {
  Test1 = { --Testa o método de inicialização
    testConnect = function(self)
      local connection = Openbus.connectByAddress(host, port, nil)
      Check.assertNotNil(connection)
      connection:close()
      local orb = Openbus.createORB(props)
      connection = Openbus.connectByAddress(host, port, orb)
      Check.assertNotNil(connection)
      connection:close()
    end,

    testConnectNullHost = function(self)
      Check.assertNil(Openbus.connectByAddress(nil, port, nil))
    end,

    testConnectNegativePort = function(self)
      Check.assertError(Openbus.connectByAddress, Openbus, host, -1, nil)
    end,

    testConnectInvalidPort = function(self)
      Check.assertError(Openbus.connectByAddress, Openbus, host, "INVALID", nil)
    end,

    testConnectTwice = function(self)
      local connection = Openbus.connectByAddress(host, port, nil)
      Check.assertNotNil(connection)
      local connection2 = Openbus.connectByAddress(host, port, nil)
      Check.assertNotNil(connection2)
      connection:close()
      connection2:close()
    end,
  },

  Test2 = {
    beforeEachTest = function(self)
      local orb = Openbus.createORB(props)
      self.connection = Openbus.connectByAddress(host, port, orb)
    end,

    afterEachTest = function(self)
      self.connection:close()
    end,

    testLoginByPassword = function(self)
      Check.assertNil(self.connection:loginByPassword(user, password))
      Check.assertTrue(self.connection:logout())
    end,

    testLoginByPasswordLoginNull = function(self)
      Check.assertError(self.connection.loginByPassword, self.connection, nil, password)
    end,

    testLoginByPasswordInvalidLogin = function(self)
      Check.assertError(self.connection.loginByPassword, self.connection, "INVALID", password)
    end,

    testLoginByPasswordTwice = function(self)
      Check.assertNil(self.connection:loginByPassword(user, password))
      Check.assertError(self.connection.loginByPassword, self.connection, user, password)
      Check.assertTrue(self.connection:logout())
    end,

--TODO: metodos q eram loginByCredential ainda precisam de testes porque o metodo encodeLogin nao esta implementado
--[[
    testShareLogin = function(self)
      Check.assertFalse(self.connection:isLoggedIn())
      Check.assertTrue(self.connection:loginByPassword(user, password))
      local credential = Openbus:getCredential()
      Check.assertNotNil(credential)
      Check.assertNotNil(Openbus:connectByCredential(credential))
      Check.assertTrue(Openbus:disconnect())
    end,

    testLoginByCredentialNullCredential = function(self)
      Check.assertNil(Openbus:connectByCredential(nil))
    end,

    testLoginByCredentialInvalidCredential = function(self)
      Check.assertNotNil(Openbus:connectByLoginPassword(user, password))
      local credential = Openbus:getCredential()
      Check.assertNotNil(credential)
      Check.assertTrue(Openbus:disconnect())
      Check.assertNil(Openbus:connectByCredential(credential))
    end,
--]]

    testIsLoggedIn = function(self)
      Check.assertFalse(self.connection:isLoggedIn())
      Check.assertNil(self.connection:loginByPassword(user, password))
      Check.assertTrue(self.connection:isLoggedIn())
      Check.assertTrue(self.connection:logout())
    end,

    testLoggedOut = function(self)
      Check.assertFalse(self.connection:isLoggedIn())
    end,

    testGetOrb = function(self)
      Check.assertNotNil(self.connection.orb)
    end,

    testGetLoginFacets = function(self)
      local LoginServiceNames = {
        AccessControl = "AccessControl",
        certificates = "CertificateRegistry",
        logins = "LoginRegistry",
      }
      for field, name in pairs(LoginServiceNames) do
        Check.assertNotNil(self.connection[field])
      end
    end,

    testGetOfferFacets = function(self)
      local OfferServiceNames = {
        interfaces = "InterfaceRegistry",
        entities = "EntityRegistry",
        offers = "OfferRegistry",
      }
      for field, name in pairs(OfferServiceNames) do
        Check.assertNotNil(self.connection[field])
      end
    end,

--TODO: testes abaixo nao estao passando pois onLoginTerminated nao esta sendo chamado.
--[[
    testCredentialExpired = function(self)
      Check.assertNotNil(self.connection.orb)
      Log:action("<< Teste da validade do lease >>")

      Check.assertNil(self.connection:loginByPassword(user, password))
      self.connection.onLoginTerminated = function(self) self.wasExpired = true end
      self.connection.isExpired = function(self) return self.wasExpired end
      Check.assertTrue(self.connection:isLoggedIn())
      self.connection:logout()
      while (not (self.connection:isExpired())) do
        Log:uptime("Lease não expirou: esperando 30 segundos...")
        oil.sleep(30)
      end
      Check.assertFalse(self.connection:logout())
    end,

    testAddOnLoginTerminatedCbAfterConnect = function(self)
      Check.assertNotNil(self.connection.orb)
      Log:action("<< Teste da reconexão após a lease não ser mais válida [Callback cadastrada depois do connect] >>")

      Check.assertNil(self.connection:loginByPassword(user, password))
      self.connection.onLoginTerminated = function(self)
          Check.assertNil(self.connection:loginByPassword(user, password))
          self.wasReconnected = true
        end
      self.connection.isReconnected = function(self) return self.wasReconnected end
      Check.assertTrue(self.connection:isLoggedIn())
      self.connection:logout()
      while (not (self.connection:isReconnected())) do
        Log:uptime("Lease não expirou: esperando 30 segundos...")
        oil.sleep(30)
      end
      Check.assertTrue(self.connection:logout())
    end,

    testAddOnLoginTerminatedCbBeforeConnect = function(self)
      Check.assertNotNil(self.connection.orb)
      Log:action("<< Teste da reconexão após a lease não ser mais válida [Callback cadastrada antes do connect] >>")

      self.connection.onLoginTerminated = function(self)
          Check.assertNil(self.connection:loginByPassword(user, password))
          self.wasReconnected = true
        end
      self.connection.isReconnected = function(self) return self.wasReconnected end
      Check.assertNil(self.connection:loginByPassword(user, password))
      Check.assertTrue(self.connection:isLoggedIn())
      self.connection:logout()
      while (not (self.connection:isReconnected())) do
        Log:uptime("Lease não expirou: esperando 30 segundos...")
        oil.sleep(30)
      end
      Check.assertTrue(self.connection:logout())
    end,
--]]
  },

  Test3 = { -- Testa loginByCertificate
    beforeTestCase = function(self)
      local ltime = tostring(socket.gettime())
      ltime = string.gsub(ltime, "%.", "")

      self.categoryId = "TesteBarramento".. ltime
      self.entityId = self.categoryId

      os.execute("echo -e '\n\n\n\n\n\n\n' | openssl-generate.ksh -n " 
          .. self.categoryId .. " 2> genkey-err.txt >genkeyT.txt ")
      
      os.execute(busadmin.." --add-category=".. self.categoryId ..
          " --name=Teste_do_OpenBus" .. logoutput)
      
      os.execute(busadmin.." --add-entity="..self.entityId ..
          " --category="..self.categoryId .. " --name=Teste_do_Barramento" ..
          logoutput)
      
      os.execute(busadmin.." --add-certificate="..self.entityId ..
          " --certificate="..self.entityId..".crt"..logoutput)
      
      self.testKeyFile = self.categoryId .. ".key"
      local keyFile = assert(io.open(self.testKeyFile))
      self.testKey = keyFile:read("*a")
      self.testKey = lce.key.readprivatefrompemstring(self.testKey)
      keyFile:close()

      local orb = Openbus.createORB(props)
      self.connection = Openbus.connectByAddress(host, port, orb)
    end,

    afterTestCase = function(self)
      local OPENBUS_HOME = os.getenv("OPENBUS_HOME")
      os.execute(busadmin.." --del-entity="..self.entityId..logoutput)
      os.execute(busadmin.." --del-category="..self.categoryId..logoutput)

      --Apaga as chaves e certificados gerados
      os.execute("rm -f " .. self.categoryId .. ".key")
      os.execute("rm -f " .. self.categoryId .. ".crt")
    end,

    afterEachTest = function(self)
      self.connection:logout()
    end,

    testConnectByCertificate = function(self)
      Check.assertNil(self.connection:loginByCertificate(self.entityId,
          self.testKey))
      Check.assertTrue(self.connection:logout())
    end,

    testConnectByCertificateNullKey = function(self)
      Check.assertError(self.connection.loginByCertificate, self.connection, self.entityId, nil)
    end,

    testConnectByCertificateInvalidEntityName = function(self)
      Check.assertError(self.connection.loginByCertificate, self.connection, nil, self.testKey)
    end,

    --TODO: verificar se aqui deve dar erro ou nao na nova API
    testConnectByCertificateTwice = function(self)
      Check.assertNil(self.connection:loginByCertificate(self.entityId,
          self.testKey))
      Check.assertError(self.connection.loginByCertificate, self.connection, self.entityId,
          self.testKey)
      Check.assertTrue(self.connection:logout())
    end,
  },
}
