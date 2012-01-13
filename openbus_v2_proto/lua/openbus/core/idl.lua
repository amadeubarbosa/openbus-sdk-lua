local _G = require "_G"
local error = _G.error
local ipairs = _G.ipairs

local array = require "table"
local unpack = array.unpack or _G.unpack

local makeaux = require "openbus.core.idl.makeaux"
local parsed = require "openbus.core.idl.parsed"



local types, const, throw = {}, {}, {}
for _, parsed in ipairs(parsed) do
	if parsed.name == "tecgraf" then
		makeaux(parsed, types, const, throw)
	end
end

local idl = {
	types = types.tecgraf.openbus.core.v2_00,
	const = const.tecgraf.openbus.core.v2_00,
	throw = throw.tecgraf.openbus.core.v2_00,
}

do
	local const = idl.const
	const.Version = "2_00"
	const.BusEntity = "OpenBus"
	const.BusObjectKey = "OpenBus"
	local const = idl.const.services.access_control
	const.AccessControlFacet = "AccessControl_2_00"
	const.LoginRegistryFacet = "LoginRegistry_2_00"
	const.CertificateRegistryFacet = "CertificateRegistry_2_00"
	const.NoLoginCode           = 0x42555300 -- "BUS\0" - 1112888064
	const.InvalidLoginCode      = 0x42555301 -- "BUS\1" - 1112888065
	const.UnverifiedLoginCode   = 0x42555302 -- "BUS\2" - 1112888066
	const.InvalidRemoteCode     = 0x42555303 -- "BUS\3" - 1112888067
	const.InvalidResetCode      = 0x42555304 -- "BUS\4" - 1112888068
	const.DeniedLoginCode       = 0x42555305 -- "BUS\5" - 1112888069
	const.InvalidCredentialCode = 0x42555306 -- "BUS\6" - 1112888070
	const.InvalidChainCode      = 0x42555307 -- "BUS\7" - 1112888071
	const.UnknownBusCode        = 0x42555308 -- "BUS\8" - 1112888072
	local const = idl.const.services.offer_registry
	const.OfferRegistryFacet = "OfferRegistry_2_00"
	const.EntityRegistryFacet = "EntityRegistry_2_00"
	const.InterfaceRegistryFacet = "InterfaceRegistry_2_00"
end

local ServiceFailure = idl.throw.services.ServiceFailure
function idl.serviceAssertion(ok, errmsg, ...)
	if not ok then ServiceFailure{message = errmsg or "assertion failed"} end
	return ok, errmsg, ...
end

function idl.loadto(orb)
	orb.TypeRepository.registry:register(unpack(parsed))
end

return idl
