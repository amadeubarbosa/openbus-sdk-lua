local _G = require "_G"
local assert = _G.assert
local pcall = _G.pcall
local giop = require "oil.corba.giop"
local openbus = require "openbus"
local idl = require "openbus.core.idl"
local log = require "openbus.util.logger"

local sysex = giop.SystemExceptionIDs

bushost, busport, verbose = ...
require "openbus.test.configs"

syskey = assert(openbus.readKeyFile(syskey))

local connprops = { accesskey = openbus.newKey() }

local orb = openbus.initORB()
local OpenBusContext = orb.OpenBusContext
assert(OpenBusContext.orb == orb)

local FakeEntity = "FakeEntity"

do log:TEST("Import chain from token")
  local conn = OpenBusContext:createConnection(bushost, busport, connprops)
  conn:loginByPassword(user, password, domain)
  local busid = conn.busid
  local login = conn.login.id
  local entity = conn.login.entity

  OpenBusContext:setDefaultConnection(conn)
  local token = entity.."@"..login..": ExternalOriginator, ExternalCaller"
  local imported = OpenBusContext:importChain(token, domain)
  assert(imported.busid == busid)
  assert(imported.target == entity)
  assert(imported.caller.id == "<unknown>")
  assert(imported.caller.entity == "ExternalCaller")
  assert(imported.originators[1].id == "<unknown>")
  assert(imported.originators[1].entity == "ExternalOriginator")
  assert(#imported.originators == 1)

  OpenBusContext:joinChain(imported)
  local joined = OpenBusContext:makeChainFor(FakeEntity)
  OpenBusContext:exitChain()

  assert(joined.busid == busid)
  assert(joined.target == FakeEntity)
  assert(joined.caller.id == login)
  assert(joined.caller.entity == entity)
  assert(joined.originators[2].id == "<unknown>")
  assert(joined.originators[2].entity == "ExternalCaller")
  assert(joined.originators[1].id == "<unknown>")
  assert(joined.originators[1].entity == "ExternalOriginator")
  assert(#joined.originators == 2)

  OpenBusContext:setDefaultConnection(nil)
  conn:logout()
end

do log:TEST("Fail to import chain from token of unknown domain")
  local conn = OpenBusContext:createConnection(bushost, busport, connprops)
  conn:loginByPassword(user, password, domain)
  OpenBusContext:setDefaultConnection(conn)
  
  local token = conn.login.entity.."@"..conn.login.id..": ExternalOriginator, ExternalCaller"
  local ok, ex = pcall(OpenBusContext.importChain, OpenBusContext, token, "UnknownDomain")
  assert(ok == false)
  assert(ex._repid == idl.types.services.access_control.UnknownDomain)
  assert(ex.domain == "UnknownDomain")
  
  OpenBusContext:setDefaultConnection(nil)
  conn:logout()
end

do log:TEST("Fail to import chain from invalid token")
  local conn = OpenBusContext:createConnection(bushost, busport, connprops)
  conn:loginByPassword(user, password, domain)
  OpenBusContext:setDefaultConnection(conn)
  
  local ok, ex = pcall(OpenBusContext.importChain, OpenBusContext, "FakeToken", domain)
  assert(ok == false)
  assert(ex._repid == idl.types.services.access_control.InvalidToken)
  assert(ex.message == "malformed test token")
  
  OpenBusContext:setDefaultConnection(nil)
  conn:logout()
end

orb:shutdown()
