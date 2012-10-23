-- $Id$

local _G = require "_G"
local assert = _G.assert
local ipairs = _G.ipairs
local loadfile = _G.loadfile
local pairs = _G.pairs
local pcall = _G.pcall
local setmetatable = _G.setmetatable

local os = require "os"
local removefile = os.remove
local renamefile = os.rename
local tmpname = os.tmpname

local io = require "io"
local open = io.open

local lfs = require "lfs"
local listdir = lfs.dir
local getattribute = lfs.attributes
local makedir = lfs.mkdir
local removedir = lfs.rmdir

local Viewer = require "loop.debug.Viewer"

local oo = require "openbus.util.oo"
local class = oo.class


local Serializer = Viewer{ nolabels = true }


local function createpath(path)
  local result, errmsg = getattribute(path, "mode")
  if result == "directory" then
    result, errmsg = true, nil
  elseif result ~= nil then
    result, errmsg = false, "'"..path..
                            "' expected to be directory (got "..result..")"
  elseif errmsg:match("^cannot obtain information") then
    result, errmsg = makedir(path)
    if not result then
      errmsg = "unable to create directory '"..path.."' ("..errmsg..")"
    end
  end
  return result, errmsg
end

local function removepath(path)
  for filename in listdir(path) do
    local filepath = path..filename
    if filename:find("%.lua$")
    and getattribute(filepath, "mode") == "file" then
      local ok, errmsg = removefile(filepath)
      if ok == nil then
        return nil, "unable to remove file '"..filepath.."' ("..errmsg..")"
      end
    end
  end
  local ok, errmsg = removedir(path)
  if ok == nil then
    return nil, "unable to remove directory '"..path.."' ("..errmsg..")"
  end
  return true
end

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

local function saveto(path, ...)
  local temp = path..".tmp" -- must be in the same path
                            -- of the final file because
                            -- 'os.rename' can only
                            -- rename files in the same
                            -- file system.
  local result, errmsg = open(temp, "w")
  if result == nil then
    errmsg = "unable to create temporary file '"..temp.."' ("..errmsg..")"
  else
    local file = result
    result, errmsg = file:write("return ", Serializer:tostring(...))
    file:close()
    if result == nil then
      errmsg = "unable to write temporary file '"..temp.."' ("..errmsg..")"
    else
      result, errmsg = renamefile(temp, path)
      if result == nil then
        errmsg = "unable to replace file '"..path.."' (with file "..errmsg..")"
      end
    end
    removefile(temp)
  end
  return result, errmsg
end

local function closeobject(obj)
  obj.path = nil
  setmetatable(obj, nil)
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

function Table:setentry(key, ...)
  return saveto(self.path..key..".lua", ...)
end

function Table:setentryfield(key, field, ...)
  local path = self.path..key..".lua"
  local result, errmsg = loadfrom(path)
  if result == nil then
    if errmsg ~= nil then
      return result, errmsg
    end
    result = {}
  end
  local count = select("#", ...)
  local value = select(count, ...)
  for i = 1, count-1 do
    local field = select(i, ...)
    local value = result[field]
    if value == nil then value = {} end
    result[field] = value
    result = value
  end
  result[field] = value
  result, errmsg = saveto(path, result)
  return result, errmsg
end

function Table:removeentry(key)
  local path = self.path..key..".lua"
  local ok, errmsg = removefile(path)
  if ok == nil then
    return nil, "unable to remove file '"..path.."' ("..errmsg..")"
  end
  return true
end

function Table:ientries()
  return self.iterator, listdir(self.path)
end

function Table:remove()
  local result, errmsg = removepath(self.path)
  if result then
    self.base.tables[self.name] = nil
    self.base, self.name = nil, nil
    closeobject(self)
  end
  return result, errmsg
end


local TableNamePat = "[^.][^/\\?*]*"

local DataBase = class()

function DataBase:__init()
  local path = self.path
  local tables = {}
  for name in listdir(path) do
    local tablepath = path..name.."/"
    if name:match(TableNamePat)
    and getattribute(tablepath, "mode") == "directory" then
      tables[name] = Table{ base = self, name = name, path = tablepath }
    end
  end
  self.tables = tables
end

function DataBase:gettable(name)
  local table = self.tables[name]
  if table == nil then
    local path = self.path..name
    local result, errmsg = createpath(path)
    if not result then
      return nil, errmsg
    end
    table = Table{ base = self, name = name, path = path.."/" }
    self.tables[name] = table
  end
  return table
end

function DataBase:itables()
  return pairs(self.tables)
end

function DataBase:close()
  for name, table in pairs(self.tables) do
    closeobject(table)
  end
  closeobject(self)
  return true
end


local module = {}

function module.open(path)
  local result, errmsg = createpath(path)
  if not result then return nil, errmsg end
  return DataBase{ path = path.."/" }
end

return module
