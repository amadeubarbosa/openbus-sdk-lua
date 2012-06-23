local Matcher = require "loop.debug.Matcher"
local Viewer = require("loop.debug.Viewer"){linebreak=" ",identation=""}

local Data = {
  Users = {
    JohnDoe = {name="John Doe",age=34,male=true},
    JaneDoe = {name="Jane Doe",age=24,male=false},
    BabyDoe = {name="Baby Doe",age=0.2},
  },
  Certifiers = {
    JohnDoe = "4ABA81F8-7A42-11E0-A71F-001FF3565357",
    JaneDoe = "5C9D8EB0-7A42-11E0-A71F-001FF3565357",
    BabyDoe = "5D809AC0-7A42-11E0-A71F-001FF3565357",
  },
}

local database = require "openbus.util.database"

do
  local db = assert(database.open("test.db"))
  for name, contents in pairs(Data) do
    local table = db:gettable(name)
    for key, value in pairs(contents) do
      assert(table:setentry(key, value))
    end
  end
end

do
  local function checktable(name, table)
    local contents = Data[name]
    for key, value in pairs(contents) do
      assert(Matcher():match(table:getentry(key), value))
    end
    for key, value in table:ientries() do
      assert(Matcher():match(value, contents[key]))
    end
  end
  
  local db = assert(database.open("test.db"))
  for name, table in db:itables() do
    checktable(name, table)
  end
  for name in pairs(Data) do
    local table = db:gettable(name)
    checktable(name, table)
    assert(table:remove())
  end
end

do
  assert(os.execute("chmod 000 test.db") == 0)
  local ok, err = pcall(database.open, "test.db")
  assert(ok == false)
  assert(err:find("cannot open test.db/: Permission denied", 1, true))
  assert(os.execute("chmod 755 test.db") == 0)
  
  local db = assert(database.open("test.db"))
  assert(io.open("test.db/ErrorTable", "w")):close()
  local ok, err = db:gettable("ErrorTable")
  assert(ok == nil)
  assert(err == "'test.db/ErrorTable' expected to be directory (got file)")
  
  local db = assert(database.open("test.db"))
  local ok, err = db:gettable("ErrorTable")
  assert(ok == nil)
  assert(err == "'test.db/ErrorTable' expected to be directory (got file)")
  
  local ok, err = db:gettable("ErrorTable/")
  assert(ok == nil)
  assert(err == "unable to create directory 'test.db/ErrorTable/' (Not a directory)")
  
  os.remove("test.db/ErrorTable")
end

do
  local db = assert(database.open("test.db"))
  local table = assert(db:gettable("Table"))
  local file = assert(io.open("test.db/Table/error.lua", "w"))
  assert(file:write("illegal Lua code") == true)
  file:close()
  
  local entry, err = table:getentry("missing")
  assert(entry == nil)
  assert(err == nil)
  
  local entry, err = table:getentry("error")
  assert(entry == nil)
  assert(err == "unable to load file 'test.db/Table/error.lua' (test.db/Table/error.lua:1: '=' expected near 'Lua')")
  
  assert(os.execute("chmod 000 test.db/Table") == 0)
  
  local entry, err = table:getentry("error")
  assert(entry == nil)
  assert(err == "unable to load file 'test.db/Table/error.lua' (cannot open test.db/Table/error.lua: Permission denied)")
  
  local ok, err = table:setentry("error", {"vazio"})
  assert(not ok)
  assert(err:match("unable to create temporary file 'test%.db/Table/error%.lua%.tmp' %(.-: Permission denied%)"))
  
  local ok, err = table:removeentry("error")
  assert(not ok)
  assert(err:match("unable to remove file 'test%.db/Table/error%.lua' %(.-: Permission denied%)"))
  
  assert(os.execute("chmod 755 test.db/Table") == 0)
  assert(os.execute("chmod 555 test.db") == 0)
  
  local ok, err = table:remove()
  assert(not ok)
  assert(err == "unable to remove directory 'test.db/Table/' (Permission denied)")
  
  assert(os.execute("chmod 755 test.db") == 0)
  assert(table:remove())
end

do
  local lfs = require "lfs"
  assert(lfs.rmdir("test.db"))
end
