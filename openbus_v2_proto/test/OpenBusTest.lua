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

local bus = require "openbus"
local multiplexer = require "openbus.multiplexed"
local idl = require "openbus.core.idl"
local Log = require "openbus.util.logger"

local orb = oil.init {flavor = "cooperative;corba.intercepted",}

local host = "localhost"
local port = 2089
local port2 = 2090
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
port2 = props:getTagOrDefault("host.port2", port2)
user = props:getTagOrDefault("user", user)
password = props:getTagOrDefault("password", password)
sdkLogLevel = props:getTagOrDefault("openbus.verbose", sdkLogLevel)
oilLogLevel = props:getTagOrDefault("oil.verbose", oilLogLevel)

oil.verbose:level(oilLogLevel)
Log:level(sdkLogLevel)

local openbus

local OPENBUS_HOME = os.getenv("OPENBUS_HOME")
local busadmin = OPENBUS_HOME .. "/bin/busadmin --host="..host.." --port="..port..
    " --login="..user.." --password=".. password
local logoutput = " 2>>management-err.txt >>management.txt "

local function toStandardBus(self)
  openbus = bus
  self.connection = self.conn
end

local function toMultiplexedBus(self)
  openbus = multiplexer
  self.connection = self.connM
end

local function testBothAPIs(self, f)
  toStandardBus(self)
  f(self)
  toMultiplexedBus(self)
  f(self)
end

local function createORBsAndConnect(self)
  local temp = openbus
  openbus = bus
  local orb = openbus.createORB(props)
  self.conn = openbus.connectByAddress(host, port, orb)
  openbus = multiplexer
  local orb2 = openbus.createORB(props)
  self.connM = openbus.connectByAddress(host, port, orb2)
  openbus = temp
end

local function disconnect(self)
  self.conn:close()
  self.connM:close()
  self.connection = nil
end

local function connect(self)
  local connection = openbus.connectByAddress(host, port, nil)
  Check.assertNotNil(connection)
  connection:close()
  local orb = openbus.createORB(props)
  connection = openbus.connectByAddress(host, port, orb)
  Check.assertNotNil(connection)
  connection:close()
end

local function connectNullHost(self)
  Check.assertError(openbus.connectByAddress, nil, port, nil)
end

local function connectNegativePort(self)
  Check.assertError(openbus.connectByAddress, openbus, host, -1, nil)
end

local function connectInvalidPort(self)
  Check.assertError(openbus.connectByAddress, openbus, host, "INVALID", nil)
end

local function connectTwice(self)
  local orb = openbus.createORB(props)
  local connection = openbus.connectByAddress(host, port, orb)
  Check.assertNotNil(connection)
  -- Nova conex�o com ORB diferente deve ser bem sucedida
  local connection2 = openbus.connectByAddress(host, port, nil)
  Check.assertNotNil(connection2)
  -- Nova conex�o com um mesmo ORB deve resultar em erro
  Check.assertError(openbus.connectByAddress, openbus, host, port, orb)
  connection:close()
  connection2:close()
end

local function loginByPassword(self)
  Check.assertNil(self.connection:loginByPassword(user, password))
  Check.assertTrue(self.connection:logout())
end

local function loginByPasswordLoginNull(self)
  Check.assertError(self.connection.loginByPassword, self.connection, nil, password)
end

local function loginByPasswordInvalidLogin(self)
  Check.assertError(self.connection.loginByPassword, self.connection, "INVALID", password)
end

local function loginByPasswordTwice(self)
  Check.assertNil(self.connection:loginByPassword(user, password))
  Check.assertError(self.connection.loginByPassword, self.connection, user, password)
  Check.assertTrue(self.connection:logout())
end

--TODO: metodos q eram loginByCredential ainda precisam de testes porque o metodo encodeLogin nao esta implementado
--[[
local function shareLogin(self)
  Check.assertFalse(self.connection:isLoggedIn())
  Check.assertTrue(self.connection:loginByPassword(user, password))
  local credential = openbus:getCredential()
  Check.assertNotNil(credential)
  Check.assertNotNil(openbus:connectByCredential(credential))
  Check.assertTrue(openbus:disconnect())
end

local function loginByCredentialNullCredential(self)
  Check.assertNil(openbus:connectByCredential(nil))
end

local function loginByCredentialInvalidCredential(self)
  Check.assertNotNil(openbus:connectByLoginPassword(user, password))
  local credential = openbus:getCredential()
  Check.assertNotNil(credential)
  Check.assertTrue(openbus:disconnect())
  Check.assertNil(openbus:connectByCredential(credential))
end
--]]
local function isLoggedIn(self)
  Check.assertFalse(self.connection:isLoggedIn())
  Check.assertNil(self.connection:loginByPassword(user, password))
  Check.assertTrue(self.connection:isLoggedIn())
  Check.assertTrue(self.connection:logout())
end

local function loggedOut(self)
  Check.assertFalse(self.connection:isLoggedIn())
end

local function getOrb(self)
  Check.assertNotNil(self.connection.orb)
end

local function getLoginFacets(self)
  local LoginServiceNames = {
    AccessControl = "AccessControl",
    certificates = "CertificateRegistry",
    logins = "LoginRegistry",
  }
  for field, name in pairs(LoginServiceNames) do
    Check.assertNotNil(self.connection[field])
  end
end

local function getOfferFacets(self)
  local OfferServiceNames = {
    interfaces = "InterfaceRegistry",
    entities = "EntityRegistry",
    offers = "OfferRegistry",
  }
  for field, name in pairs(OfferServiceNames) do
    Check.assertNotNil(self.connection[field])
  end
end

local function loginBecameInvalidDuringCall(self)
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
end

local function loginBecameInvalidDuringRenew(self)
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
end

local function reconnectOnInvalidLoginDuringCall(self)
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
end

local function reconnectOnInvalidLoginDuringRenew(self)
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
end

local function onInvalidLoginErrorDuringCall(self)
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
end

local function onInvalidLoginErrorDuringRenew(self)
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
end

local function connectByCertificate(self)
  Check.assertNil(self.connection:loginByCertificate(self.entityId,
      self.testKey))
  Check.assertTrue(self.connection:logout())
end

local function connectByCertificateNullKey(self)
  Check.assertError(self.connection.loginByCertificate, self.connection, self.entityId, nil)
end

local function connectByCertificateInvalidEntityName(self)
  Check.assertError(self.connection.loginByCertificate, self.connection, nil, self.testKey)
end

    --TODO: verificar se aqui deve dar erro ou nao na nova API
local function connectByCertificateTwice(self)
  Check.assertNil(self.connection:loginByCertificate(self.entityId,
      self.testKey))
  Check.assertError(self.connection.loginByCertificate, self.connection, self.entityId,
      self.testKey)
  Check.assertTrue(self.connection:logout())
end

Suite = {
  Test1 = { --Testa o m�todo de inicializa��o
    testConnect = function(self)
      testBothAPIs(self, connect)
    end,

    testConnectNullHost = function(self)
      testBothAPIs(self, connectNullHost)
    end,

    testConnectNegativePort = function(self)
      testBothAPIs(self, connectNegativePort)
    end,

    testConnectInvalidPort = function(self)
      testBothAPIs(self, connectInvalidPort)
    end,

    testConnectTwice = function(self)
      testBothAPIs(self, connectTwice)
    end,
  },

  Test2 = { -- Testes b�sicos e comuns das APIs padr�o e multiplexada
    beforeEachTest = function(self)
      createORBsAndConnect(self)
    end,

    afterEachTest = function(self)
      disconnect(self)
    end,

    testLoginByPassword = function(self)
      testBothAPIs(self, loginByPassword)
    end,

    testLoginByPasswordLoginNull = function(self)
      testBothAPIs(self, loginByPasswordLoginNull)
    end,

    testLoginByPasswordInvalidLogin = function(self)
      testBothAPIs(self, loginByPasswordLoginNull)
    end,

    testLoginByPasswordTwice = function(self)
      testBothAPIs(self, loginByPasswordTwice)
    end,

    testShareLogin = function(self)
--TODO: metodos q eram loginByCredential ainda precisam de testes porque o metodo encodeLogin nao esta implementado
    end,

    testLoginByCredentialNullCredential = function(self)
--TODO: metodos q eram loginByCredential ainda precisam de testes porque o metodo encodeLogin nao esta implementado
    end,

    testLoginByCredentialInvalidCredential = function(self)
--TODO: metodos q eram loginByCredential ainda precisam de testes porque o metodo encodeLogin nao esta implementado
    end,

    testIsLoggedIn = function(self)
      testBothAPIs(self, isLoggedIn)
    end,

    testLoggedOut = function(self)
      testBothAPIs(self, loggedOut)
    end,

    testGetOrb = function(self)
      testBothAPIs(self, getOrb)
    end,

    testGetLoginFacets = function(self)
      testBothAPIs(self, getLoginFacets)
    end,

    testGetOfferFacets = function(self)
      testBothAPIs(self, getOfferFacets)
    end,

    testLoginBecameInvalidDuringCall = function(self)
      testBothAPIs(self, loginBecameInvalidDuringCall)
    end,

    testLoginBecameInvalidDuringRenew = function(self)
      testBothAPIs(self, loginBecameInvalidDuringRenew)
    end,

    testReconnectOnInvalidLoginDuringCall = function(self)
      testBothAPIs(self, reconnectOnInvalidLoginDuringCall)
    end,

    testReconnectOnInvalidLoginDuringRenew = function(self)
      testBothAPIs(self, reconnectOnInvalidLoginDuringRenew)
    end,

    testOnInvalidLoginErrorDuringCall = function(self)
      testBothAPIs(self, onInvalidLoginErrorDuringCall)
    end,

    testOnInvalidLoginErrorDuringRenew = function(self)
      testBothAPIs(self, onInvalidLoginErrorDuringRenew)
    end,
  },

  Test3 = { -- Testes b�sicos de certificado
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

      createORBsAndConnect(self)
    end,

    afterTestCase = function(self)
      os.execute(busadmin.." --del-entity="..self.entityId..logoutput)
      os.execute(busadmin.." --del-category="..self.categoryId..logoutput)

      --Apaga as chaves e certificados gerados
      os.execute("rm -f " .. self.categoryId .. ".key")
      os.execute("rm -f " .. self.categoryId .. ".crt")
    end,

    afterEachTest = function(self)
      self.conn:logout()
      self.connM:logout()
    end,

    testConnectByCertificate = function(self)
      testBothAPIs(self, connectByCertificate)
    end,

    testConnectByCertificateNullKey = function(self)
      testBothAPIs(self, connectByCertificateNullKey)
    end,

    testConnectByCertificateInvalidEntityName = function(self)
      testBothAPIs(self, connectByCertificateInvalidEntityName)
    end,

    --TODO: verificar se aqui deve dar erro ou nao na nova API
    testConnectByCertificateTwice = function(self)
      testBothAPIs(self, connectByCertificateTwice)
    end,
  },

  Test4 = { --Testes espec�ficos de multiplexa��o
  --TODO: adicionar testes.
  },
}
