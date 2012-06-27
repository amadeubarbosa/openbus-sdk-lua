local _G = require "_G"
local error = _G.error
local ipairs = _G.ipairs

local array = require "table"
local unpack = array.unpack or _G.unpack

local debug = require "debug"
local traceback = debug.traceback

local makeaux = require "openbus.core.idl.makeaux"
local parsed = require "openbus.core.idl.parsed"



local types, const, throw = {}, {}, {}
for _, parsed in ipairs(parsed) do
  if parsed.name == "tecgraf" then
    makeaux(parsed, types, const, throw)
  end
end

local idl = {
  types = types.tecgraf.openbus.core.v2_0,
  const = const.tecgraf.openbus.core.v2_0,
  throw = throw.tecgraf.openbus.core.v2_0,
}

local ServiceFailure
do
  local failure = idl.throw.services.ServiceFailure
  function ServiceFailure(fields)
    fields.stacktrace = traceback()
    return failure(fields)
  end
  idl.throw.services.ServiceFailure = ServiceFailure
end

function idl.serviceAssertion(ok, errmsg, ...)
  if not ok then ServiceFailure{message = errmsg or "assertion failed"} end
  return ok, errmsg, ...
end

function idl.loadto(orb)
  orb.TypeRepository.registry:register(unpack(parsed))
end

return idl
