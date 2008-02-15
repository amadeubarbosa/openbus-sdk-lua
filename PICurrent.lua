-- $Id$

local oil = require "oil"
local oop = require "loop.base"

local setmetatable = setmetatable

---
--Objeto que permite a transferência de informações de um interceptador
--para o tratador de uma requisição de serviço.
---
module("openbus.common.PICurrent", oop.class)

---
--Constrói o objeto.
--
--@return O objeto.
---
function __init(self)

  -- Os valores transferidos serão armazenados em uma tabela de chaves fracas.
  -- As chaves dessa tabela são as corotinas associadas às requisições.
  -- Assumimos que o oil cria uma nova corotina para cada requisição

  local picurrentTable = {}
  setmetatable(picurrentTable, {__mode = "k"})
  return oop.rawnew(self, {picurrentTable = picurrentTable})
end

---
--Insere um valor na tabela de transferência
--
--@param value O valor.
---
function setValue(self, value)
  self.picurrentTable[oil.tasks.current] = value
end

---
--Obtém um valor da tabela de transferência
--
--@return O valor.
---
function getValue(self)
  return self.picurrentTable[oil.tasks.current]
end
