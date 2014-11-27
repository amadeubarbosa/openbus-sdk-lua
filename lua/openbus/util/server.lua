local _G = require "_G"
local assert = _G.assert
local error = _G.error
local getenv = _G.getenv
local ipairs = _G.ipairs
local loadfile = _G.loadfile
local next = _G.next
local pairs = _G.pairs
local setmetatable = _G.setmetatable
local tostring = _G.tostring
local type = _G.type
local xpcall = _G.xpcall

local array = require "table"
local concat = array.concat

local string = require "string"
local substring = string.sub

local math = require "math"
local ceil = math.ceil

local io = require "io"
local openfile = io.open
local stderr = io.stderr

local debug = require "debug"
local traceback = debug.traceback

local pubkey = require "lce.pubkey"
local decodeprivatekey = pubkey.decodeprivate
local x509 = require "lce.x509"
local decodecertificate = x509.decode

local Arguments = require "loop.compiler.Arguments"

local ComponentContext = require "scs.core.ComponentContext"

local log = require "openbus.util.logger"
local msg = require "openbus.util.messages"
local oo = require "openbus.util.oo"
local class = oo.class



local module = {}



local SafeEnv = {__index = { error = error, getenv = getenv }}

local function defaultAdd(list, value)
  list[#list+1] = tostring(value)
end

function module.setuplog(log, level, path, mode)
  log:level(level)
  if path ~= nil and path ~= "" then
    local file, errmsg = openfile(path, mode or "a")
    if file == nil then
      log:misconfig(msg.BadLogFile:tag{path=path,errmsg=errmsg})
    else
      log.viewer.output = file
      return path
    end
  end
end

function module.readfrom(path, mode)
  local result, errmsg = openfile(path, mode or "rb")
  if result then
    local file = result
    result, errmsg = file:read("*a")
    file:close()
    if result then
      return result
    end
  end
  return nil, msg.UnableToReadFileContents:tag{ path = path, errmsg = errmsg }
end

local readfrom = module.readfrom

function module.readpublickey(path)
  local encoded, errmsg = readfrom(path)
  if encoded ~= nil then
    local certificate
    certificate, errmsg = decodecertificate(encoded)
    if certificate then
      local key
      key, errmsg = certificate:getpubkey()
      if key then return key, encoded end
      errmsg = msg.UnableToObtainPublicKey:tag{ path = path, errmsg = errmsg }
    end
    errmsg = msg.UnableToDecodeCertificate:tag{ path = path, errmsg = errmsg }
  end
  return nil, errmsg
end

function module.readprivatekey(path)
  local key, errmsg = readfrom(path)
  if key ~= nil then
    key, errmsg = decodeprivatekey(key)
    if key then return key end
    errmsg = msg.UnableToDecodePrivateKey:tag{ path = path, errmsg = errmsg }
  end
  return nil, errmsg
end

function module.blockencrypt(key, operation, blocksize, stream)
  local result = {}
  for i = 1, ceil(#stream/blocksize) do
    local block = substring(stream, 1+(i-1)*blocksize, i*blocksize)
    local piece, errmsg = key[operation](key, block)
    if piece == nil then return nil, errmsg end
    result[#result+1] = piece
  end
  return concat(result)
end

function module.newSCS(params)
  -- cria um componente SCS
  local component = ComponentContext(params.orb, { -- component id
    name = params.name or "unamed SCS component",
    major_version = params.major_version or 1,
    minor_version = params.minor_version or 0,
    patch_version = params.patch_version or 0,
    platform_spec = params.platform_spec or "",
  }, { -- keys
    IComponent = params.objkey,
  })

  -- adiciona as facetas e receptáculos do componente
  local facets = params.facets
  for name, obj in pairs(facets) do
    component:addFacet(obj.__facet or obj.__objkey,obj.__type,obj,obj.__objkey)
  end
  local receptacles = params.receptacles
  if receptacles ~= nil then
    for name, iface in pairs(receptacles) do
      local conn
      if type(iface) ~= "string" then
        iface, conn = iface.__type, iface
      end
      component:addReceptacle(name, iface)
      if conn ~= nil then
        local receptacles = component.IComponent:getFacetByName("IReceptacles")
        receptacles:connect(name, conn)
      end
    end
  end
  
  function component:getConnected(name)
    local receptDesc = self._receptacles[name]
    if receptDesc ~= nil then
      local _, connDesc = next(receptDesc.connections)
      if connDesc then
        return connDesc.objref
      end
    end
  end
  
  -- inicia o componente
  function component.IComponent:startup()
    for name, obj in pairs(facets) do
      if obj.startup ~= nil then
        obj:startup()
      end
    end
  end
  local shutdown = params.shutdown
  function component.IComponent:shutdown()
    for name, obj in pairs(facets) do
      if obj.shutdown ~= nil then
        obj:shutdown()
      end
    end
    if shutdown ~= nil then shutdown() end
    local errors = self.context:deactivateComponent()
    for name, error in pairs(errors) do
      errors[#errors+1] = tostring(error)
    end
    assert(errors == 0, concat(errors, "\n"))
  end
  local init = params.init
  if init ~= nil then init() end
  
  return component
end



module.ConfigArgs = class({
  __call = Arguments.__call, -- no metamethod inheritance
  -- mensagens de erro nos argumentos de linha de comando
  _badnumber = "valor do parâmetro '%s' é inválido (número esperado ao invés de '%s')",
  _missing = "nenhum valor definido para o parâmetro '%s'",
  _unknown = "parâmetro '%s' é desconhecido",
  _norepeat = "parâmetro '%s' só pode ser definido uma vez",
}, Arguments)

function module.ConfigArgs:configs(_, path)
  local sandbox = setmetatable({}, SafeEnv)
  local result, errmsg = loadfile(path, "t", sandbox)
  if result ~= nil then
    result, errmsg = xpcall(result, traceback)
    if result then
      for name, value in pairs(sandbox) do
        local kind = type(self[name])
        if kind == "nil" then
          log:misconfig(msg.BadParamInConfigFile:tag{
            configname = name,
            path = path,
          })
          self[name] = value
        elseif kind ~= type(value) then
          log:misconfig(msg.BadParamTypeInConfigFile:tag{
            configname = name,
            path = path,
            expected = kind,
            actual = type(value),
          })
        elseif kind == "table" then
          local list = self[name]
          local add = list.add or defaultAdd
          for index, value in ipairs(value) do
            local errmsg = add(list, tostring(value))
            if errmsg ~= nil then
              log:misconfig(msg.BadParamListInConfigFile:tag{
                configname = name,
                index = index,
                path = path,
              })
            end
          end
        else
          self[name] = value
        end
      end
      log:config(msg.ConfigFileLoaded:tag{path=path})
    else
      log:misconfig(msg.UnableToLoadConfigFile:tag{path=path,errmsg=errmsg})
    end
  else
    log:misconfig(msg.UnableToLoadConfigFile:tag{path=path,errmsg=errmsg})
  end
end



return module