local openbus = require "openbus"
local log = require "openbus.util.logger"
local oil = require "oil"

require "openbus.test.util"

-- customize test configuration for this case
settestcfg(...)

-- setup and start the ORB
local orb = openbus.initORB(orbcfg)

-- get bus context manager
local OpenBusContext = orb.OpenBusContext

-- connect to the bus
local conn = OpenBusContext:createConnection(bushost, busport)
OpenBusContext:setDefaultConnection(conn)

-- login to the bus
conn:loginByPassword(user, password)

-- serialize shared authentication data
local secret = conn:startSharedAuth()
local encoded = OpenBusContext:encodeSharedAuth(secret)
assert(oil.writeto(sharedauthfile, encoded, "wb"))

log:TEST("shared authentication data written to file!")

-- logout from the bus
conn:logout()
orb:shutdown()
