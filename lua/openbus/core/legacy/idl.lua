local _G = require "_G"
local ipairs = _G.ipairs

local array = require "table"
local unpack = array.unpack or _G.unpack

local debug = require "debug"
local traceback = debug.traceback

local makeaux = require "openbus.core.idl.makeaux"
local parsed = require "openbus.core.legacy.parsed"



local types, const, throw = {}, {}, {}
for _, parsed in ipairs(parsed) do
  if parsed.name == "tecgraf" then
    makeaux(parsed, types, const, throw)
  end
end

local idl = {
  types = types.tecgraf.openbus.core,
  const = const.tecgraf.openbus.core,
  throw = throw.tecgraf.openbus.core,
}

local ServiceFailure
do
  local failure = idl.throw.v2_0.services.ServiceFailure
  function ServiceFailure(fields)
    fields.stacktrace = traceback()
    return failure(fields)
  end
  idl.throw.v2_0.services.ServiceFailure = ServiceFailure
end

function idl.serviceAssertion(ok, errmsg, ...)
  if not ok then ServiceFailure{message = errmsg or "assertion failed"} end
  return ok, errmsg, ...
end

function idl.loadto(orb)
  orb.TypeRepository.registry:register(unpack(parsed))
end

return idl
