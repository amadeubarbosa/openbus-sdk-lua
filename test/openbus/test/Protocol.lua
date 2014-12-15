bushost, busport = ...
require "openbus.test.configs"
require "openbus.test.lowlevel"

local coroutine = require "coroutine"
local newthread = coroutine.create

local cothread = require "cothread"
local startthread = cothread.next
local sleep = cothread.delay

local pubkey = require "lce.pubkey"
local newkey = pubkey.create
local decodeprvkey = pubkey.decodeprivate

local idl = require "openbus.core.idl"
local EncryptedBlockSize = idl.const.EncryptedBlockSize

local server = require "openbus.util.server"
local readfrom = server.readfrom

syskey = assert(decodeprvkey(readfrom(syskey)))

-- test initialization ---------------------------------------------------------

do -- connect to the bus
  local bus, orb = connectToBus(readfrom(busref, "r"))
  local accesskey = newkey(EncryptedBlockSize)
  local otherkey = newkey(EncryptedBlockSize)

  -- login to the bus
  local login, lease = loginByPassword(bus, user, password, accesskey)

  -- start renewer thread
  startthread(newthread(function ()
    local AccessControl = bus.AccessControl
    repeat
      login.busSession:newCred("renew")
      local ok, lease = pcall(AccessControl.renew, AccessControl)
      if ok then sleep(lease) end
    until not ok
  end))

  -- get offered services
  login.busSession:newCred("getAllServices")
  offers = bus.OfferRegistry:getAllServices()

  -- test found services
  local function isfalse(value) assert(value == false) end
  local function isnotnil(value) assert(value ~= nil) end
  for _, offer in ipairs(offers) do
    local service = offer.service_ref
    local ok, result = pcall(service._non_existent, service)
    if (ok and not result)
    or (not ok and result._repid ~= "IDL:omg.org/CORBA/TRANSIENT:1.0") then
      testBusCall(bus, login, otherkey, isnotnil, service, "getComponentId")
    end
  end

  -- logout from the bus
  login.busSession:newCred("logout")
  bus.AccessControl:logout()
  orb:shutdown()
end
