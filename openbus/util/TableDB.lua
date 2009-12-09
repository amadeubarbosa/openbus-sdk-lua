-- $Id$

local oo         = require "loop.base"
local lfs        = require "lfs"
local uuid       = require "uuid"
local Viewer     = require "loop.debug.Viewer"

local os     = require "os"
local io     = require "io"
local string = require "string"

local pairs    = pairs
local error    = error
local print    = print
local assert   = assert
local pcall    = pcall
local setfenv  = setfenv
local loadfile = loadfile
--
-- Classe que gerencia dados em disco.  Esses dados são tuplas
-- <chave,valor> -- abstração de tabela em Lua.  Ao atribuir um novo
-- valor a um chave, o valor antigo é sobrescrito.
--
module("openbus.util.TableDB", oo.class)

---
-- Constrói um objeto do banco de dados.
--
-- @param dbfile Arquivo para armazenar as informações. Esse arquivo é
-- cricado caso não exista.
--
function __init(self, dbfile)
   local mode = lfs.attributes(dbfile, "mode")
   if not mode then
      local f = assert(io.open(dbfile, "w"))
      f:close()
   elseif mode ~= "file" then
      error("Arquivo de banco de dados inválido.")
   end
   return oo.rawnew(self, { dbfile = dbfile })
end

---
-- Salva um valor relacionado a uma chave.
-- Se a chave já possui valor atribuído, ele é sobrescrito.
--
-- @param key Chave para identificar o valor.
-- @param value Valor a ser persistido.
--
-- @return  Retorna true  se  o  valor foi  salvo  com sucesso. Caso
-- contrário false e uma mensagem de erro.
--
function save(self, key, value)
   local data, msg = self:loadAll()
   if not data then
      return false, msg
   end
   data[key] = value
   return self:saveAll(data)
end

--
-- Remove o par <key,value> referente à chave informada.
--
-- @param key Chave que identifica o par.
--
-- @return  Retorna true  se o  par  foi removido  com sucesso.   Caso
-- contrário retorna false e uma mensagem de erro.
--
function remove(self, key)
   local data, msg = self:loadAll()
   if not data then
      return false, msg
   end
   data[key] = nil
   return self:saveAll(data)
end

---
-- Recupera todos os valores armazenados. Não há ordem nos dados.
--
-- @return Retorna  uma seqüência (array) dos  valores armazenados nas
-- chaves.  Em  caso de erro, retorna  nil seguido de  uma mensagem de
-- erro.
--
function getValues(self)
   local data, msg = self:loadAll()
   if not data then
      return nil, msg
   end
   local array = {}
   for k, v in pairs(data) do
      array[#array+1] = v
   end
   return array
end

---
-- Recupera o valor referente a uma chave.
--
-- @return Em caso de erro, retorna  nil e uma mensagem de erro.  Caso
--   contrário, retorna o valor da chave. Nota: se a chave não existe,
--   retorna apenas nil.
--
function get(self, key)
   local data, msg = self:loadAll()
   if not data then
      return nil, msg
   end
   return data[key]
end

--
-- Função interna que recupera os dados persistidos no disco.
--
-- @return  Retorna uma  tabela contendo  os dados.  Em caso  de erro,
-- retorna nil seguido de uma mensagem de erro.
--
function loadAll(self)
   local reader, msg = loadfile(self.dbfile)
   if not reader then
      msg = string.format("Erro ao carregar dados do disco: %s", msg)
      return nil, msg
   end
   -- Sandbox
   setfenv(reader, {})
   local succ, data = pcall(reader)
   if not succ then
      data = string.format("Erro ao carregar dados do disco: %s", data)
      return nil, data
   end
   -- Arquivo vazio, criar uma lista vazia
   return (data or {})
end

---
-- Função interna para persistir as informações dos pares em disco.
--
-- Esta  função tenta preservar  os dados  antigos gerando  um arquivo
-- temporário para salvar  os novos dados e só  então remove o arquivo
-- antigo e renomeia o novo arquivo para o nome definitivo.
--
-- @param data A tabela a ser pesistida em disco.
--
-- @return Retorna true se os dados foram salvos com sucesso.
--
function saveAll(self, data)
   local f, msg, succ
   local tmp = string.format("%s-%s.tmp", self.dbfile, uuid.new("time"))
   f, msg = io.open(tmp, "w")
   if not f then
      return false, msg
   end
   local writer = Viewer{ output = f }
   -- Simula try/catch
   succ, msg = pcall(function()
      assert(f:write("return "))
      -- writer não retorna nada, não há como capturar um erro
      writer:writeto(f, data)
      -- Essa escrita pode ajudar no erro acima, se houver
      assert(f:write("\n"))
      assert(f:close())
   end)
   if not succ then
      os.remove(tmp)
      msg = string.format("Não foi possível criar a nova base: %s", msg)
      return false, msg
   end
   succ, msg = os.remove(self.dbfile)
   if not succ then
      msg = string.format("Não foi possível remover base antiga: %s", msg)
      return false, msg
   end
   succ, msg = os.rename(tmp, self.dbfile)
   if not succ then
      msg = string.format("Não foi possível renomear a nova base: %s", msg)
      return false, msg
   end
   return true
end
