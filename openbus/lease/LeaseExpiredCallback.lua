-- $Id: LeaseExpiredCallback.lua $

local oop = require "loop.base"
local set = require "loop.collection.UnorderedArraySet"

local type = type

---
-- API de adição de callbacks para expiração de lease.
---
module ("openbus.lease.LeaseExpiredCallback", oop.class)

---
-- Construtor.
---
function __init(self)
  return oop.rawnew(self, { callbacks = set() })
end

---
-- O <i>lease</i> expirou e não será mais renovado pelo {@link LeaseRenewer}
---
function expired(self)
  if #(self.callbacks) == 0 then
    return
  end
  local i = 1
  repeat
    self.callbacks[i]:expired()
    i = i + 1
  until i > #(self.callbacks)
end

---
-- Adiciona um observador para receber eventos de expiração do <i>lease</i>.
--
-- @param lec O observador. Deve ser um objeto, contendo um metodo expired().
--
-- @return {@code true}, caso o observador seja adicionado, ou {@code false}
--         , caso contrário.
---
function addLeaseExpiredCallback(self, lec)
  if not lec.expired or type(lec.expired) ~= "function" then
    return false
  end
  if self.callbacks:add(lec) then
    return true
  end
  return false
end

---
-- Remove um observador de expiração do <i>lease</i>.
--
-- @param lec O observador.
--
-- @return {@code true}, caso o observador seja removido, ou {@code false},
--         caso contrário.
---
function removeLeaseExpiredCallback(self, lec)
  if self.callbacks:remove(lec) then
    return true
  end
  return false
end
