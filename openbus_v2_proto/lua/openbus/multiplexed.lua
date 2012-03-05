local _G = require "_G"
local next = _G.next
local pairs = _G.pairs
local pcall = _G.pcall
local setmetatable = _G.setmetatable

local coroutine = require "coroutine"
local newthread = coroutine.create

local table = require "loop.table"
local copy = table.copy
local memoize = table.memoize

local cothread = require "cothread"
local running = cothread.running

local oo = require "openbus.util.oo"
local class = oo.class

local log = require "openbus.util.logger"
local msg = require "openbus.util.messages"

local idl = require "openbus.core.idl"
local const = idl.const.services.access_control
local Identifier = idl.types.Identifier
local BusObjectKey = idl.const.BusObjectKey

local access = require "openbus.core.Access"
local neworb = access.createORB

local openbus = require "openbus"
local basicORB = openbus.createORB
local connectByAddress = openbus.connectByAddress

local VersionHeader = "\002\000"
local CredentialContextId = 0x42555300 -- "BUS\0"

local WeakKeyMeta = { __mode = "k" }


local IceptorOp2LogMessage = {
  sendrequest = msg.MultiplexedCall,
  receivereply = false,
  receiverequest = msg.GotMultiplexedCall,
  sendreply = false,
}

local function logMultiplexed(conn, op, request, ...)
  local message = IceptorOp2LogMessage[op]
  if message then
    local login = conn.login
    log:multiplexed(true, IceptorOp2LogMessage[op]:tag{
      bus = conn.busid,
      login = login and login.id,
      entity = login and login.entity,
      operation = request.operation.name,
    })
  end
  conn[op](conn, request, ...)
  if not message then
    log:multiplexed(false)
  end
end

local function getBusId(self, contexts)
  local data = contexts[CredentialContextId]
  if data ~= nil then
    local decoder = self.orb:newdecoder(data)
    return decoder:get(self.identifierType)
  end
end



local Multiplexer = class()

function Multiplexer:__init()
  self.connections = {} -- [conn] = { [thread]=true, ... }
  self.connectionOf = setmetatable({}, WeakKeyMeta) -- [thread]=connection
  local orb = self.orb
  self.identifierType = orb.types:lookup_id(Identifier)
end

function Multiplexer:addConnection(conn)
  self.connections[conn] = {}
end

function Multiplexer:removeConnection(conn)
  local connections = self.connections
  local threads = connections[conn]
  if threads then
    local connectionOf = self.connectionOf
    connectionOf[conn.busid] = nil
    for thread in pairs(threads) do
      connectionOf[thread] = nil
    end
    connections[conn] = nil
  end
end

function Multiplexer:sendrequest(request, ...)
  local conn = self.connectionOf[running()]
  if conn ~= nil then
    request.multiplexedConnection = conn
    logMultiplexed(conn, "sendrequest", request, ...)
  else
    request.success = false
    request.results = {self.orb:newexcept{
      "CORBA::NO_PERMISSION",
      completed = "COMPLETED_NO",
      minor = const.NoLoginCode,
    }}
    log:badaccess(msg.CallInThreadWithoutConnection:tag{
      operation = request.operation.name,
    })
  end
end

function Multiplexer:receivereply(request, ...)
  local conn = request.multiplexedConnection
  logMultiplexed(conn, "receivereply", request, ...)
  if request.success ~= nil then
    request.multiplexedConnection = nil
  end
end

function Multiplexer:receiverequest(request, ...)
  local ok, busid = pcall(getBusId, self, request.service_context)
  if ok then
    local conn = self.connectionOf[busid]
    if conn ~= nil then
      request.multiplexedConnection = conn
      self.connectionOf[running()] = conn
      logMultiplexed(conn, "receiverequest", request, ...)
    else
      request.success = false
      request.results = {self.orb:newexcept{
        "CORBA::NO_PERMISSION",
        completed = "COMPLETED_NO",
        minor = const.UnknownBusCode,
      }}
      log:badaccess(msg.DeniedCallFromUnknownBus:tag{
        operation = request.operation.name,
        bus = busid,
      })
    end
  else
    request.success = false
    request.results = { callers } -- TODO[maia]: Is a good CORBA SysEx to throw here?
    log:badaccess(msg.UnableToDecodeCredential:tag{errmsg=callers})
  end
end

function Multiplexer:sendreply(request, ...)
  local conn = request.multiplexedConnection
  logMultiplexed(conn, "sendreply", request, ...)
  request.multiplexedConnection = nil
  self.connectionOf[running()] = nil
end

function Multiplexer:setCurrentConnection(conn)
  local set = self.connections[conn]
  if set == nil then error("invalid connection") end
  local thread = running()
  self.connectionOf[thread] = conn
  set[thread] = true
end

function Multiplexer:getCurrentConnection()
  return self.connectionOf[running()]
end

function Multiplexer:setIncomingConnection(busid, conn)
  if self.connections[conn] == nil or conn.busid ~= busid then
    error("invalid connection")
  end
  self.connectionOf[busid] = conn
end

function Multiplexer:getIncomingConnection(busid)
  return self.connectionOf[busid]
end



local function createORB(...)
  local orb = basicORB(...)
  local multiplexer = Multiplexer{ orb = orb }
  orb.OpenBusConnectionMultiplexer = multiplexer
  -- redefine interceptor operations
  local iceptor = orb.OpenBusInterceptor
  function iceptor:addConnection(conn)
    local current = self.connection
    if current == nil then
      self.connection = conn
    else
      if current ~= multiplexer then
        multiplexer:addConnection(current)
        self.connection = multiplexer
        log:multiplexed(msg.MultiplexingEnabled)
      end
      multiplexer:addConnection(conn)
    end
  end
  local removeConnection = iceptor.removeConnection
  function iceptor:removeConnection(conn)
    local current = self.connection
    if self.connection ~= multiplexer then
      removeConnection(self, conn)
    else
      multiplexer:removeConnection(conn)
      local connections = multiplexer.connections
      local single = next(connections)
      if single ~= nil and next(connections, single) == nil then
        multiplexer:removeConnection(single)
        self.connection = single
        log:multiplexed(msg.MultiplexingDisabled)
      end
    end
  end
  return orb
end



local openbus = { createORB = createORB }

function openbus.connectByAddress(host, port, orb)
  if orb == nil then orb = createORB() end
  local conn = connectByAddress(host, port, orb)
  local multiplexer = orb.OpenBusConnectionMultiplexer
  local renewer = conn.newrenewer
  function conn:newrenewer(lease)
    local thread = renewer(self, lease)
    multiplexer.connectionOf[thread] = conn
    return thread
  end
  return conn
end



-- insert function argument typing
local argcheck = require "openbus.util.argcheck"
argcheck.convertclass(Multiplexer, {
  setCurrentConnection = { --[[Connection]] },
  getCurrentConnection = {},
  setIncomingConnection = { "string", --[[Connection]] },
  getIncomingConnection = { "string" },
})
argcheck.convertmodule(openbus, {
  createORB = { "nil|table" },
  connectByAddress = { "string", "number" },
})



return openbus
