local _G = require "_G"
local assert = _G.assert
local ipairs = _G.ipairs
local loadfile = _G.loadfile
local pairs = _G.pairs
local pcall = _G.pcall

local lfs = require "lfs"
local listdir = lfs.dir
local getattribute = lfs.attributes

local Viewer = require "loop.debug.Viewer"

local oo = require "openbus.util.oo"
local class = oo.class

local Serializer = Viewer{ nolabels = true }

local function loadfrom_cont(path, ok, ...)
  if ok then return ... end
  local errmsg = ...
  return nil, "corrupted file '"..path.."' ("..errmsg..")"
end

local function loadfrom(path)
  local result, errmsg = loadfile(path, "t", {})
  if result == nil then
    if errmsg:find("No such file or directory") then
      return
    end
    return nil, "unable to load file '"..path.."' ("..errmsg..")"
  end
  return loadfrom_cont(path, pcall(result))
end

local Table = class()

function Table:__init()
  function self.iterator(next)
    local file = next()
    while file ~= nil do
      local path = self.path..file
      if getattribute(path, "mode") == "file" then
        return file:match("^(.+)%.lua$"), assert(loadfrom(path))
      end
      file = next()
    end
  end
end

function Table:getentry(key)
  return loadfrom(self.path..key..".lua")
end

function Table:ientries()
  return self.iterator, listdir(self.path)
end


local TableNamePat = "[^.][^/\\?*]*"

local DataBase = class()

function DataBase:__init()
  local path = self.path
  local schema = {    
    "AutoSetttings",
    "Categories",
    "Certificates",
    "Entities",
    "Interfaces",
    "LoginObservers",
    "Logins",
    "OfferRegistryObservers",
    "Offers"
  }
  local tables = {}
  for _, name in ipairs(schema) do
    local tablepath = path..name.."/"
    if name:match(TableNamePat)
    and getattribute(tablepath, "mode") == "directory" then
      tables[name] = Table{ base = self, name = name, path = tablepath }
    else
       error('corrupted database')
    end
  end
  self.tables = tables
end

function DataBase:gettable(name)
  return self.tables[name]
end

function DataBase:itables()
  return pairs(self.tables)
end

local module = {}

function module.open(path)
  if getattribute(path, "mode") ~= "directory" then return nil end
  local res, db = pcall(DataBase, { path = path.."/" })
  if res then return db else return nil end
end

return module
