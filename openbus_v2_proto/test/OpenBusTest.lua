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
local Check = require "latt.Check"

local openbus = require "openbus"
local idl = require "openbus.core.idl"
local Log = require "openbus.util.logger"
local server = require "openbus.util.server"

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

host = props:getTagOrDefault("host.name", host)
port = props:getTagOrDefault("host.port", port)
user = props:getTagOrDefault("user", user)
password = props:getTagOrDefault("password", password)
sdkLogLevel = props:getTagOrDefault("openbus.verbose", sdkLogLevel)
oilLogLevel = props:getTagOrDefault("oil.verbose", oilLogLevel)

oil.verbose:level(oilLogLevel)
Log:level(sdkLogLevel)

local busadmin = "busadmin --host="..host.." --port="..port..
    " --login="..user.." --password=".. password
local logoutput = " 2>>management-err.txt >>management.txt "


Suite = {
  Test1 = { --Testa o m�todo de inicializa��o
    testConnect = function(self)
      local connection = openbus.connectByAddress(host, port, nil)
      Check.assertNotNil(connection)
      connection:close()
      local orb = openbus.createORB(props)
      connection = openbus.connectByAddress(host, port, orb)
      Check.assertNotNil(connection)
      connection:close()
    end,

    testConnectNullHost = function(self)
      Check.assertError(openbus.connectByAddress, nil, port, nil)
    end,

    testConnectNegativePort = function(self)
      Check.assertError(openbus.connectByAddress, openbus, host, -1, nil)
    end,

    testConnectInvalidPort = function(self)
      Check.assertError(openbus.connectByAddress, openbus, host, "INVALID", nil)
    end,

    testConnectTwice = function(self)
      local connection = openbus.connectByAddress(host, port, nil)
      Check.assertNotNil(connection)
      local connection2 = openbus.connectByAddress(host, port, nil)
      Check.assertNotNil(connection2)
      connection:close()
      connection2:close()
    end,
  },

  Test2 = {
    beforeEachTest = function(self)
      local orb = openbus.createORB(props)
      self.connection = openbus.connectByAddress(host, port, orb)
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
      local credential = openbus:getCredential()
      Check.assertNotNil(credential)
      Check.assertNotNil(openbus:connectByCredential(credential))
      Check.assertTrue(openbus:disconnect())
    end,

    testLoginByCredentialNullCredential = function(self)
      Check.assertNil(openbus:connectByCredential(nil))
    end,

    testLoginByCredentialInvalidCredential = function(self)
      Check.assertNotNil(openbus:connectByLoginPassword(user, password))
      local credential = openbus:getCredential()
      Check.assertNotNil(credential)
      Check.assertTrue(openbus:disconnect())
      Check.assertNil(openbus:connectByCredential(credential))
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

    testLoginBecameInvalidDuringCall = function(self)
      local conn = self.connection
      Log:action("<< Teste do login ficar invalido durante uma chamada >>")

      local isInvalid = false
      function conn:onInvalidLogin()
        isInvalid = true
      end

      conn:loginByPassword(user, password)
      conn.logins:invalidateLogin(conn.login.id) -- force login to become invalid
      -- perform a invocation with an invalid login
      local offers = conn.offers
      local ok, ex = pcall(offers.getServices, offers)
      Check.assertFalse(ok)
      Check.assertEquals("IDL:omg.org/CORBA/NO_PERMISSION:1.0", ex._repid)
      Check.assertEquals("COMPLETED_NO", ex.completed)
      Check.assertEquals(idl.const.services.access_control.InvalidLoginCode, ex.minor)

      Check.assertTrue(isInvalid)
      Check.assertFalse(conn:isLoggedIn())
    end,

    testLoginBecameInvalidDuringRenew = function(self)
      local conn = self.connection
      Log:action("<< Teste do login ficar invalido antes de sua renova��o >>")

      local isInvalid = false
      function conn:onInvalidLogin()
        isInvalid = true
      end

      conn:loginByPassword(user, password)
      local validity = conn.logins:getValidity{conn.login.id}[1]
      conn.logins:invalidateLogin(conn.login.id) -- force login to become invalid
      oil.sleep(validity+2) -- wait for the attempt to renew the login

      Check.assertTrue(isInvalid)
      Check.assertFalse(conn:isLoggedIn())
    end,

    testReconnectOnInvalidLoginDuringCall = function(self)
      local conn = self.connection
      Log:action("<< Teste da reconex�o ap�s o login ficar inv�lido >>")

      local wasReconnected = false
      function conn:onInvalidLogin()
        self:loginByPassword(user, password)
        wasReconnected = true
        return true -- retry invocation
      end

      conn:loginByPassword(user, password)
      conn.logins:invalidateLogin(conn.login.id) -- force login to become invalid
      conn.offers:getServices()
      Check.assertTrue(wasReconnected)
      Check.assertTrue(self.connection:logout())
    end,

    testReconnectOnInvalidLoginDuringRenew = function(self)
      local conn = self.connection
      Log:action("<< Teste da reconex�o ap�s o login ficar inv�lido >>")

      local wasReconnected = false
      function conn:onInvalidLogin()
        self:loginByPassword(user, password)
        wasReconnected = true
        return true -- retry invocation
      end

      conn:loginByPassword(user, password)
      local validity = conn.logins:getValidity{conn.login.id}[1]
      conn.logins:invalidateLogin(conn.login.id) -- force login to become invalid
      oil.sleep(validity+2) -- wait for the attempt to renew the login
      Check.assertTrue(wasReconnected)
      Check.assertTrue(self.connection:logout())
    end,

    testOnInvalidLoginErrorDuringCall = function(self)
      local conn = self.connection
      Log:action("<< Teste de erro lan�ado na callback 'onInvalidLogin' >>")

      function conn:onInvalidLogin()
        error("Oops!")
      end

      conn:loginByPassword(user, password)
      conn.logins:invalidateLogin(conn.login.id) -- force login to become invalid
      local offers = conn.offers
      local ok, ex = pcall(offers.getServices, offers)
      Check.assertFalse(ok)
      Check.assertNotNil(ex:match("Oops!$"))
    end,

    testOnInvalidLoginErrorDuringRenew = function(self)
      local conn = self.connection
      Log:action("<< Teste de erro lan�ado na callback 'onInvalidLogin' >>")

      local wasReconnected = false
      function conn:onInvalidLogin()
        error("Oops!")
      end

      conn:loginByPassword(user, password)
      local validity = conn.logins:getValidity{conn.login.id}[1]
      conn.logins:invalidateLogin(conn.login.id) -- force login to become invalid
      oil.sleep(validity+2) -- wait for the attempt to renew the login
      Check.assertFalse(conn:isLoggedIn())
    end,
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
      self.testKey = server.readprivatekey(self.testKeyFile)

      local orb = openbus.createORB(props)
      self.connection = openbus.connectByAddress(host, port, orb)
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
