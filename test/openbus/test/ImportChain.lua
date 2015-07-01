local _G = require "_G"
local assert = _G.assert
local pcall = _G.pcall
local uuid = require "uuid"
local giop = require "oil.corba.giop"
local openbus = require "openbus"
local idl = require "openbus.core.idl"
local log = require "openbus.util.logger"
local util = require "openbus.util.server"

local sysex = giop.SystemExceptionIDs

require "openbus.test.util"

setorbcfg(...)

busref = assert(util.readfrom(busref, "r"))
syskey = assert(openbus.readKeyFile(syskey))

local connprops = { accesskey = openbus.newKey() }

local orb = openbus.initORB(orbcfg)
local OpenBusContext = orb.OpenBusContext
assert(OpenBusContext.orb == orb)
busref = orb:newproxy(busref, nil, "::scs::core::IComponent")

local FakeEntity = "FakeEntity"

for _, count in ipairs{0, 1, 10, 100} do
  log:TEST("Import chain with "..count.." originators from token")

  local conn = OpenBusContext:connectByReference(busref, connprops)
  conn:loginByPassword(user, password, domain)
  local busid = conn.busid
  local login = conn.login.id
  local entity = conn.login.entity

  local originators = {}
  for i = 1, count do
    originators[i] = "ExternalOriginator"..i
  end

  OpenBusContext:setDefaultConnection(conn)
  local prefix = #originators>0 and table.concat(originators, ", ")..", " or ""
  local token = entity.."@"..login..": "..prefix.."ExternalCaller"

  local imported = OpenBusContext:importChain(token, domain)
  assert(imported.busid == busid)
  assert(imported.target == entity)
  assert(uuid.isvalid(imported.caller.id))
  assert(imported.caller.entity == "ExternalCaller")
  assert(#imported.originators == #originators)
  for index, entity in ipairs(originators) do
    assert(uuid.isvalid(imported.originators[index].id))
    assert(imported.originators[index].entity == "ExternalOriginator"..index)
  end

  OpenBusContext:joinChain(imported)
  local joined = OpenBusContext:makeChainFor(FakeEntity)
  OpenBusContext:exitChain()

  assert(joined.busid == busid)
  assert(joined.target == FakeEntity)
  assert(joined.caller.id == login)
  assert(joined.caller.entity == entity)
  assert(#joined.originators == 1+#originators)
  for index, entity in ipairs(originators) do
    assert(uuid.isvalid(joined.originators[index].id))
    assert(joined.originators[index].entity == "ExternalOriginator"..index)
  end
  assert(uuid.isvalid(joined.originators[1+#originators].id))
  assert(joined.originators[1+#originators].entity == "ExternalCaller")

  OpenBusContext:setDefaultConnection(nil)
  conn:logout()
end

do log:TEST("Fail to import chain from token of unknown domain")
  local conn = OpenBusContext:connectByReference(busref, connprops)
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
  local conn = OpenBusContext:connectByReference(busref, connprops)
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
