local openbus = require "openbus"
local log = require "openbus.util.logger"

require "openbus.test.util"

-- customize test configuration for this case
settestcfg(...)

-- setup the ORB
local orb = openbus.initORB(orbcfg)

-- get bus context manager
local OpenBusContext = orb.OpenBusContext

-- connect to the bus
local conn = OpenBusContext:createConnection(bushost, busport)
OpenBusContext:setDefaultConnection(conn)

-- read shared authentication data
log:TEST("retrieve shared authentication data")
local secret = OpenBusContext:decodeSharedAuth(waitfile(sharedauthfile))

-- login to the bus
conn:loginBySharedAuth(secret)

-- check identity
local langs = {
	java = true,
	cpp = true,
	csharp = true,
	lua = true,
}
local lang = string.match(conn.login.entity, "interop_sharedauth_(.+)_client")
assert(langs[lang] ~= nil)

-- logout from the bus
conn:logout()
orb:shutdown()
