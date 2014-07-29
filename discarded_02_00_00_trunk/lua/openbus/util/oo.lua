local _G = require "_G"
local pairs = _G.pairs
local setmetatable = _G.setmetatable
local type = _G.type

local array = require "table"
local concat = array.concat

local multiple = require "loop.multiple"
local newclass = multiple.class
local issubclassof = multiple.issubclassof

local hierarchy = require "loop.hierarchy"
local mutator = hierarchy.mutator

-- .............................................................................
-- @class object
-- 
-- Class implicitly inherited by all created classes.
-- 
local Object = newclass{ __new = mutator }

-- .............................................................................
-- @class module
-- 
-- Offers functions that implement an object-oriented model in Lua.
-- 
-- It is entirely based in the LOOP models. Additionally it offer the class
-- 'Object' that is implicitly inherited by all created classes. The 'Object'
-- class implements a top-down constructor chain.
-- 
local oo = setmetatable({ Object = Object }, { __index = multiple })

-- .............................................................................
-- @class       function
-- @description Create a new class that implicitly inherits from class
--              'Object' if no super class is defined.
-- @param class Table that contains the members provided by the class.
-- @param ...   Optional superclasses that the new class inherits from.
-- @return      New created class.
function oo.class(class, ...)
  if issubclassof(..., Object) then
    return newclass(class, ...)
  end
  return newclass(class, Object, ...)
end

return oo
