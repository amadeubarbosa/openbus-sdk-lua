local idl = require "openbus.core.idl"
local log = require "openbus.util.logger"
local except = require "openbus.util.except"
local openbus = require "openbus"


require "openbus.test.util"

-- setup the ORB
local orb = openbus.initORB()

-- load interface definition
orb:loadidlfile("idl/mock.idl")
local iface = orb.types:lookup("tecgraf::openbus::interop::protocol::Server")

-- customize test configuration for this case
settestcfg(iface, ...)

-- get bus context manager
local OpenBusContext = orb.OpenBusContext

-- connect to the bus
local conn = OpenBusContext:createConnection(bushost, busport)
OpenBusContext:setDefaultConnection(conn)

-- login to the bus
conn:loginByPassword(user, password)

-- define service properties
properties[#properties+1] =
  {name="openbus.component.interface",value=iface.repID}

-- define test cases
local CredentialResetCases = {
  {
    session = 2^32-1,
    challenge = string.rep("\171", idl.const.EncryptedBlockSize),
    expected = except.minor.InvalidRemote,
  },
}
local NoPermisisonCases = {
  {raised=0,expected=0},
  {raised=except.minor.InvalidCredential,expected=except.minor.InvalidRemote},
  {raised=except.minor.InvalidChain,expected=except.minor.InvalidChain},
  {raised=except.minor.UnverifiedLogin,expected=except.minor.UnverifiedLogin},
  {raised=except.minor.UnknownBus,expected=except.minor.UnknownBus},
  {raised=except.minor.InvalidPublicKey,expected=except.minor.InvalidPublicKey},
  {raised=except.minor.NoCredential,expected=except.minor.NoCredential},
  {raised=except.minor.NoLogin,expected=except.minor.InvalidRemote},
  {raised=except.minor.InvalidRemote,expected=except.minor.InvalidRemote},
  {raised=except.minor.UnavailableBus,expected=except.minor.InvalidRemote},
  {raised=except.minor.InvalidTarget,expected=except.minor.InvalidRemote},
  {raised=except.minor.InvalidLogin,expected=except.minor.InvalidRemote},
}

-- find the offered service
log:TEST("retrieve hello service")
local OfferRegistry = OpenBusContext:getOfferRegistry()
for _, offer in ipairs(findoffers(OfferRegistry, properties)) do
  local entity = getprop(offer.properties, "openbus.offer.entity")
  log:TEST("found service of ",entity,"!")
  local server = offer.service_ref:getFacetByName(iface.name):__narrow(iface)
  server:NonBusCall()
  for _, case in ipairs(CredentialResetCases) do
    local ok, ex = pcall(server.ResetCredentialWithChallenge, server,
                         case.session, case.challenge)
    assert(ok == false)
    assert(ex._repid == except.repid.NO_PERMISSION)
    assert(ex.minor == case.expected)
    assert(ex.completed == "COMPLETED_NO")
  end
  for _, case in ipairs(NoPermisisonCases) do
    local ok, ex = pcall(server.RaiseNoPermission, server, case.raised)
    assert(ok == false)
    assert(ex._repid == except.repid.NO_PERMISSION)
    assert(ex.minor == case.expected)
    assert(ex.completed == "COMPLETED_NO")
  end
  log:TEST("test successful for service of ",entity)
end

-- logout from the bus
conn:logout()
orb:shutdown()
