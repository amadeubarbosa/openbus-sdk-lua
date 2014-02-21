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
  local table = db:gettable("Nested")
  local record = {
    field1 = "one",
    field2 = "two",
    field3 = "three",
  }
  assert(table:setentry("letters", record))
  assert(table:setentryfield("letters", "a", "a", "a", "aaa"))
  assert(table:setentryfield("letters", "a", "a", "b", "aab"))
  assert(table:setentryfield("letters", "a", "a", "c", "aac"))
  assert(table:setentryfield("letters", "a", "b", "a", "aba"))
  assert(table:setentryfield("letters", "a", "b", "b", "abb"))
  assert(table:setentryfield("letters", "a", "b", "c", "abc"))
  assert(table:setentryfield("letters", "a", "c", "a", "aca"))
  assert(table:setentryfield("letters", "a", "c", "b", "acb"))
  assert(table:setentryfield("letters", "a", "c", "c", "acc"))
  assert(table:setentryfield("letters", "b", "a", "a", "baa"))
  assert(table:setentryfield("letters", "b", "a", "b", "bab"))
  assert(table:setentryfield("letters", "b", "a", "c", "bac"))
  assert(table:setentryfield("letters", "b", "b", "a", "bba"))
  assert(table:setentryfield("letters", "b", "b", "b", "bbb"))
  assert(table:setentryfield("letters", "b", "b", "c", "bbc"))
  assert(table:setentryfield("letters", "b", "c", "a", "bca"))
  assert(table:setentryfield("letters", "b", "c", "b", "bcb"))
  assert(table:setentryfield("letters", "b", "c", "c", "bcc"))
  assert(table:setentryfield("letters", "c", "a", "a", "caa"))
  assert(table:setentryfield("letters", "c", "a", "b", "cab"))
  assert(table:setentryfield("letters", "c", "a", "c", "cac"))
  assert(table:setentryfield("letters", "c", "b", "a", "cba"))
  assert(table:setentryfield("letters", "c", "b", "b", "cbb"))
  assert(table:setentryfield("letters", "c", "b", "c", "cbc"))
  assert(table:setentryfield("letters", "c", "c", "a", "cca"))
  assert(table:setentryfield("letters", "c", "c", "b", "ccb"))
  assert(table:setentryfield("letters", "c", "c", "c", "ccc"))
  assert(table:setentry("numbers", record))
  assert(table:setentryfield("numbers", 1, 1, 1, "111"))
  assert(table:setentryfield("numbers", 1, 1, 2, "112"))
  assert(table:setentryfield("numbers", 1, 1, 3, "113"))
  assert(table:setentryfield("numbers", 1, 2, 1, "121"))
  assert(table:setentryfield("numbers", 1, 2, 2, "122"))
  assert(table:setentryfield("numbers", 1, 2, 3, "123"))
  assert(table:setentryfield("numbers", 1, 3, 1, "131"))
  assert(table:setentryfield("numbers", 1, 3, 2, "132"))
  assert(table:setentryfield("numbers", 1, 3, 3, "133"))
  assert(table:setentryfield("numbers", 2, 1, 1, "211"))
  assert(table:setentryfield("numbers", 2, 1, 2, "212"))
  assert(table:setentryfield("numbers", 2, 1, 3, "213"))
  assert(table:setentryfield("numbers", 2, 2, 1, "221"))
  assert(table:setentryfield("numbers", 2, 2, 2, "222"))
  assert(table:setentryfield("numbers", 2, 2, 3, "223"))
  assert(table:setentryfield("numbers", 2, 3, 1, "231"))
  assert(table:setentryfield("numbers", 2, 3, 2, "232"))
  assert(table:setentryfield("numbers", 2, 3, 3, "233"))
  assert(table:setentryfield("numbers", 3, 1, 1, "311"))
  assert(table:setentryfield("numbers", 3, 1, 2, "312"))
  assert(table:setentryfield("numbers", 3, 1, 3, "313"))
  assert(table:setentryfield("numbers", 3, 2, 1, "321"))
  assert(table:setentryfield("numbers", 3, 2, 2, "322"))
  assert(table:setentryfield("numbers", 3, 2, 3, "323"))
  assert(table:setentryfield("numbers", 3, 3, 1, "331"))
  assert(table:setentryfield("numbers", 3, 3, 2, "332"))
  assert(table:setentryfield("numbers", 3, 3, 3, "333"))
  assert(table:setentry("booleans", record))
  assert(table:setentryfield("booleans", true, true, "true true"))
  assert(table:setentryfield("booleans", true, false, "true false"))
  assert(table:setentryfield("booleans", false, true, "false true"))
  assert(table:setentryfield("booleans", false, false, "false false"))
  Data.Nested = {
    letters = {
      field1 = "one",
      field2 = "two",
      field3 = "three",
      a = {
        a = {
          a = "aaa",
          b = "aab",
          c = "aac",
        },
        b = {
          a = "aba",
          b = "abb",
          c = "abc",
        },
        c = {
          a = "aca",
          b = "acb",
          c = "acc",
        },
      },
      b = {
        a = {
          a = "baa",
          b = "bab",
          c = "bac",
        },
        b = {
          a = "bba",
          b = "bbb",
          c = "bbc",
        },
        c = {
          a = "bca",
          b = "bcb",
          c = "bcc",
        },
      },
      c = {
        a = {
          a = "caa",
          b = "cab",
          c = "cac",
        },
        b = {
          a = "cba",
          b = "cbb",
          c = "cbc",
        },
        c = {
          a = "cca",
          b = "ccb",
          c = "ccc",
        },
      },
    },
    numbers = {
      field1 = "one",
      field2 = "two",
      field3 = "three",
      [1] = {
        [1] = {
          [1] = "111",
          [2] = "112",
          [3] = "113",
        },
        [2] = {
          [1] = "121",
          [2] = "122",
          [3] = "123",
        },
        [3] = {
          [1] = "131",
          [2] = "132",
          [3] = "133",
        },
      },
      [2] = {
        [1] = {
          [1] = "211",
          [2] = "212",
          [3] = "213",
        },
        [2] = {
          [1] = "221",
          [2] = "222",
          [3] = "223",
        },
        [3] = {
          [1] = "231",
          [2] = "232",
          [3] = "233",
        },
      },
      [3] = {
        [1] = {
          [1] = "311",
          [2] = "312",
          [3] = "313",
        },
        [2] = {
          [1] = "321",
          [2] = "322",
          [3] = "323",
        },
        [3] = {
          [1] = "331",
          [2] = "332",
          [3] = "333",
        },
      },
    },
    booleans = {
      field1 = "one",
      field2 = "two",
      field3 = "three",
      [true] = {
        [true] = "true true",
        [false] = "true false",
      },
      [false] = {
        [true] = "false true",
        [false] = "false false",
      },
    },
  }
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
  assert(os.execute("chmod 000 test.db"))
  local ok, err = pcall(database.open, "test.db")
  assert(ok == false)
  assert(err:find("cannot open test.db/: Permission denied", 1, true))
  assert(os.execute("chmod 755 test.db"))
  
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
  assert(err:match("unable to create directory 'test%.db/ErrorTable/' %(.-%)"))
  
  os.remove("test.db/ErrorTable")
end

do
  local db = assert(database.open("test.db"))
  local table = assert(db:gettable("Table"))
  local file = assert(io.open("test.db/Table/error.lua", "w"))
  assert(file:write("illegal Lua code"))
  file:close()
  
  local entry, err = table:getentry("missing")
  assert(entry == nil)
  assert(err == nil)
  
  local entry, err = table:getentry("error")
  assert(entry == nil)
  assert(type(err) == "string")
  
  assert(os.execute("chmod 000 test.db/Table"))
  
  local entry, err = table:getentry("error")
  assert(entry == nil)
  assert(err == "unable to load file 'test.db/Table/error.lua' (cannot open test.db/Table/error.lua: Permission denied)")
  
  local ok, err = table:setentry("error", {"vazio"})
  assert(not ok)
  assert(err:match("unable to create temporary file 'test%.db/Table/error%.lua%.tmp' %(.-: Permission denied%)"))
  
  local ok, err = table:removeentry("error")
  assert(not ok)
  assert(err:match("unable to remove file 'test%.db/Table/error%.lua' %(.-: Permission denied%)"))
  
  assert(os.execute("chmod 755 test.db/Table"))
  assert(os.execute("chmod 555 test.db"))
  
  local ok, err = table:remove()
  assert(not ok)
  assert(err == "unable to remove directory 'test.db/Table/' (Permission denied)")
  
  assert(os.execute("chmod 755 test.db"))
  assert(table:remove())
end

do
  local lfs = require "lfs"
  assert(lfs.rmdir("test.db"))
end
