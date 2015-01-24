local _G = require "_G"
local error = _G.error
local pairs = _G.pairs
local require = _G.require
local xpcall = _G.xpcall

local bit32 = require "bit32"

local debug = require "debug"
local traceback = debug.traceback

local coroutine = require "coroutine"
local io = require "io"
local math = require "math"
local os = require "os"

local package = require "package"
local loaded = package.loaded
local preload = package.preload

local string = require "string"

local module = {}

function module.create()
  local preloaded = {}
  local packcfg = {
    preload = preloaded,
    searchpath = package.searchpath,
    path = package.path,
    config = package.config,
    cpath = package.cpath,
  }
  local allowed = {
    _G = {
      assert = _G.assert,
      dofile = _G.dofile,
      error = _G.error,
      getmetatable = _G.getmetatable,
      ipairs = _G.ipairs,
      load = _G.load,
      loadfile = _G.loadfile,
      next = _G.next,
      pairs = _G.pairs,
      pcall = _G.pcall,
      print = _G.print,
      rawequal = _G.rawequal,
      rawget = _G.rawget,
      rawlen = _G.rawlen,
      rawset = _G.rawset,
      select = _G.select,
      setmetatable = _G.setmetatable,
      tonumber = _G.tonumber,
      tostring = _G.tostring,
      type = _G.type,
      xpcall = _G.xpcall,
    },
    bit32 = {
      band = bit32.band,
      rrotate = bit32.rrotate,
      arshift = bit32.arshift,
      replace = bit32.replace,
      bor = bit32.bor,
      bxor = bit32.bxor,
      rshift = bit32.rshift,
      bnot = bit32.bnot,
      lshift = bit32.lshift,
      lrotate = bit32.lrotate,
      btest = bit32.btest,
      extract = bit32.extract,
    },
    debug = {
      traceback = debug.traceback,
    },
    coroutine = {
      create = coroutine.create,
      yield = coroutine.yield,
      resume = coroutine.resume,
      wrap = coroutine.wrap,
      status = coroutine.status,
      running = coroutine.running,
    },
    io = {
      open = io.open,
      tmpfile = io.tmpfile,
      type = io.type,
      popen = io.popen,
      flush = io.flush,
    },
    math = {
      acos = math.acos,
      atan2 = math.atan2,
      huge = math.huge,
      fmod = math.fmod,
      pi = math.pi,
      randomseed = math.randomseed,
      random = math.random,
      tanh = math.tanh,
      floor = math.floor,
      frexp = math.frexp,
      sqrt = math.sqrt,
      ceil = math.ceil,
      exp = math.exp,
      ldexp = math.ldexp,
      atan = math.atan,
      sinh = math.sinh,
      abs = math.abs,
      modf = math.modf,
      tan = math.tan,
      max = math.max,
      pow = math.pow,
      min = math.min,
      cosh = math.cosh,
      rad = math.rad,
      cos = math.cos,
      sin = math.sin,
      deg = math.deg,
      log = math.log,
      asin = math.asin,
    },
    os = {
      tmpname = os.tmpname,
      remove = os.remove,
      date = os.date,
      difftime = os.difftime,
      exit = os.exit,
      getenv = os.getenv,
      clock = os.clock,
      time = os.time,
      setlocale = os.setlocale,
      rename = os.rename,
      execute = os.execute,
    },
    package = packcfg,
    string = {
      sub = string.sub,
      char = string.char,
      upper = string.upper,
      rep = string.rep,
      lower = string.lower,
      format = string.format,
      find = string.find,
      gsub = string.gsub,
      len = string.len,
      byte = string.byte,
      dump = string.dump,
      gmatch = string.gmatch,
      reverse = string.reverse,
      match = string.match,
    },
  }
  packcfg.loaded = allowed
  local env = allowed._G
  for name, module in pairs(allowed) do
    env[name] = module
  end

  function env.require(name)
    local module = allowed[name]
    if module == nil then
      local loader = preloaded[name]
      if loader ~= nil then
        module = loader(name)
        if module == nil then
          module = true
        end
      elseif preload[name] == nil and loaded[name] == nil then
        local path, cpath = package.path, package.cpath
        package.path, package.cpath = packcfg.path, packcfg.cpath
        local ok, result = xpcall(require, traceback, name)
        package.path, package.cpath = path, cpath
        if not ok then error(result) end
        module = result
      else
        error("no permission to load module '"..name.."'")
      end
      allowed[name] = module
    end
    return module
  end

  return env
end

return module
