local openbus = require "openbus"
local log = require "openbus.util.logger"
local ComponentContext = require "scs.core.ComponentContext"

-- create service implementation
local impl, servant, iface do
  require "openbus.test.lowlevel"
  local idl = require "openbus.core.idl"
  local sysex = require "openbus.util.sysex"
  -- initialize the ORB
  local orb = initORB()
  idl.loadto(orb)
  -- load interface definition
  orb:loadidlfile("idl/mock.idl")
  iface = orb.types:lookup("tecgraf::openbus::interop::protocol::Server")
  impl = { __type = iface }
  function impl:NonBusCall(...)
    return ...
  end
  function impl:RaiseNoPermission(minor)
    sysex.NO_PERMISSION{ completed = "COMPLETED_NO", minor = minor }
  end
  function impl:ResetCredentialWithChallenge(session, challenge)
    putrepcxt(idl.const.credential.CredentialContextId, encodeReset{
      target = self.login,
      entity = self.entity,
      session = session,
      challenge = challenge,
    })
    sysex.NO_PERMISSION{
      completed = "COMPLETED_NO",
      minor = idl.const.services.access_control.InvalidCredentialCode,
    }
  end
  servant = orb:newservant(impl)
end

require "openbus.test.util"

-- customize test configuration for this case
settestcfg(...)

-- setup and start the ORB
local orb = openbus.initORB(orbcfg)

-- get bus context manager
local OpenBusContext = orb.OpenBusContext
impl.context = OpenBusContext

-- create service SCS component
local component = ComponentContext(orb, {
  name = "Mock",
  major_version = 1,
  minor_version = 0,
  patch_version = 0,
  platform_spec = "Lua",
})
component._facets[iface.name] = {
  name = iface.name,
  interface_name = iface.repID,
  facet_ref = servant,
  implementation = impl,
}
component[iface.name] = servant

-- connect to the bus
local conn = OpenBusContext:createConnection(bushost, busport)
OpenBusContext:setDefaultConnection(conn)

-- login to the bus
conn:loginByCertificate(system, assert(openbus.readKeyFile(syskey)))
impl.login = conn.login.id
impl.entity = conn.login.entity

-- offer service
local OfferRegistry = OpenBusContext:getOfferRegistry()
OfferRegistry:registerService(component.IComponent, properties)

log:TEST("hello service ready!")
