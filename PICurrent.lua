-- $Id$

local oil = require "oil"
local oop = require "loop.base"

local setmetatable = setmetatable

---
--Objeto que permite a transfer�ncia de informa��es de um interceptador
--para o tratador de uma requisi��o de servi�o.
---
module("openbus.common.PICurrent", oop.class)

---
--Constr�i o objeto.
--
--@return O objeto.
---
function __init(self)

  -- Os valores transferidos ser�o armazenados em uma tabela de chaves fracas.
  -- As chaves dessa tabela s�o as corotinas associadas �s requisi��es.
  -- Assumimos que o oil cria uma nova corotina para cada requisi��o

  local picurrentTable = {}
  setmetatable(picurrentTable, {__mode = "k"})
  return oop.rawnew(self, {picurrentTable = picurrentTable})
end

---
--Insere um valor na tabela de transfer�ncia
--
--@param value O valor.
---
function setValue(self, value)
  self.picurrentTable[oil.tasks.current] = value
end

---
--Obt�m um valor da tabela de transfer�ncia
--
--@return O valor.
---
function getValue(self)
  return self.picurrentTable[oil.tasks.current]
end
