local lsqlite = require "lsqlite3"

local lfs = require "lfs"
local getattribute = lfs.attributes

local log = require "openbus.util.logger"

local oo = require "openbus.util.oo"
local class = oo.class

local DataBase = class()

local SQL_create_tables = [[
  CREATE TABLE IF NOT EXISTS settings (
    key   TEXT PRIMARY KEY,
    value TEXT NOT NULL
  );
  
  CREATE TABLE IF NOT EXISTS category (
    id   TEXT PRIMARY KEY, 
    name TEXT NOT NULL
  );

  CREATE TABLE IF NOT EXISTS certificate (
    entity TEXT PRIMARY KEY,
    certificate BLOB NOT NULL
  );

  CREATE TABLE IF NOT EXISTS entity (
    id          TEXT PRIMARY KEY,
    name        TEXT,
    category TEXT NOT NULL
      REFERENCES category(id)
      ON DELETE CASCADE    
  );

  CREATE TABLE IF NOT EXISTS login (
    id                  TEXT PRIMARY KEY,
    entity              TEXT NOT NULL,
    encodedkey          BLOB NOT NULL
  );

  CREATE TABLE IF NOT EXISTS loginObserver (
    id       TEXT PRIMARY KEY,
    ior      TEXT NOT NULL,
    login TEXT NOT NULL
      REFERENCES login(id)
      ON DELETE CASCADE
  );

  CREATE TABLE IF NOT EXISTS watchedLogin (
    login_observer TEXT NOT NULL
      REFERENCES loginObserver(id)
      ON DELETE CASCADE,
    login TEXT NOT NULL
      REFERENCES login(id)
      ON DELETE CASCADE,
    CONSTRAINT pkey PRIMARY KEY (
      login_observer,
      login)
  );

  CREATE TABLE IF NOT EXISTS interface (
    repid TEXT PRIMARY KEY
  );

  CREATE TABLE IF NOT EXISTS entityInterface (
    entity    TEXT
      REFERENCES entity(id)
      ON DELETE CASCADE,
    interface TEXT
      REFERENCES interface(repid)
      ON DELETE CASCADE
  );

  CREATE TABLE IF NOT EXISTS facet (
    name           TEXT,
    interface_name TEXT,
    offer          TEXT
      REFERENCES offer(id)
      ON DELETE CASCADE
  );

  CREATE TABLE IF NOT EXISTS propertyOffer (
    name     TEXT NOT NULL,
    value    TEXT NOT NULL,
    offer    TEXT NOT NULL
      REFERENCES offer(id)
      ON DELETE CASCADE
  );

  CREATE TABLE IF NOT EXISTS propertyOfferRegistryObserver (
    name                       TEXT NOT NULL,
    value                      TEXT NOT NULL,
    offer_registry_observer    TEXT NOT NULL
      REFERENCES offerRegistryObserver(id)
      ON DELETE CASCADE
  );

  CREATE TABLE IF NOT EXISTS offer (
    id                      TEXT PRIMARY KEY,
    service_ref             TEXT NOT NULL,
    entity                  TEXT NOT NULL,
    login                   TEXT NOT NULL,
    timestamp               TEXT NOT NULL,
    day                     TEXT NOT NULL,
    month                   TEXT NOT NULL,
    year                    TEXT NOT NULL,
    hour                    TEXT NOT NULL,
    minute                  TEXT NOT NULL,
    second                  TEXT NOT NULL,
    component_name          TEXT NOT NULL,
    component_major_version TEXT NOT NULL,
    component_minor_version TEXT NOT NULL,
    component_patch_version TEXT NOT NULL,
    component_platform_spec TEXT NOT NULL
  );

  CREATE TABLE IF NOT EXISTS offerObserver (
    id       TEXT PRIMARY KEY,
    login    TEXT NOT NULL,
    observer TEXT NOT NULL,
    offer    TEXT NOT NULL
      REFERENCES offer(id)
      ON DELETE CASCADE
  );

  CREATE TABLE IF NOT EXISTS offerRegistryObserver (
    id       TEXT PRIMARY KEY,
    login    TEXT NOT NULL,
    observer TEXT NOT NULL
  );
]]

local actions = {
  -- INSERT
  { name = "addCategory",
    values = { "id", "name" } },
  { name="addEntity",
    values = { "id", "name", "category" } },
  { name="addInterface",
    values = { "repid" } },
  { name="addEntityInterface",
    values = { "entity", "interface" } },
  { name="addOffer",
    values = { "id", "service_ref", "entity", "login", "timestamp",
	       "day", "month", "year", "hour", "minute",
	       "second", "component_name", "component_major_version",
	       "component_minor_version", "component_patch_version",
	       "component_platform_spec" } },
  { name="addPropertyOffer",
    values = { "name", "value", "offer" } },
  { name="addPropertyOfferRegistryObserver",
    values = { "name", "value", "offer_registry_observer" } },
  { name="addFacet",
    values = { "name", "interface_name", "offer" } },
  { name="addOfferObserver",
    values = { "id", "login", "observer", "offer" } },
  { name="addOfferRegistryObserver",
    values = { "id", "login", "observer" } },
  { name="addSettings",
    values = { "key", "value" } },
  { name="addLogin",
    values = { "id", "entity", "encodedKey" } },
  { name="addLoginObserver",
    values = { "id", "ior", "login" } },
  { name="addWatchedLogin",
    values = { "login_observer", "login" } },
  { name="addCertificate",
    values = { "certificate", "entity" } },

  -- DELETE
  { name="delCategory",
    where = { "id" } },
  { name="delEntity",
    where = { "id" } },
  { name="delEntityInterface",
    where = { "entity", "interface" } },
  { name="delInterface",
    where = { "repid" } },
  { name="delOffer",
    where = { "id" } },
  { name="delPropertyOffer",
    where = { "offer" } },
  { name="delFacet",
    where = { "offer" } },
  { name="delOfferObserver",
    where = { "id" } },
  { name="delOfferRegistryObserver",
    where = { "id" } },
  { name="delPropertyOfferRegistryObserver",
    where = { "offer_registry_observer" } },
  { name="delLogin",
    where = { "id" } },
  { name="delLoginObserver",
    where = { "id" } },
  { name="delWatchedLogin",
    where = { "login_observer", "login" } },
  { name="delCertificate",
    where = { "entity" } },

  -- UPDATE
  { name="setCategory",
    set="name",
    where="id" },
  { name="setEntity",
    set="name",
    where="id" },
  { name="setCertificate",
    set="certificate",
    where="entity" },

  -- SELECT
  { name="getCategory",
    select = { "id", "name" } },
  { name="getCertificate",
    select = { "entity, certificate" } },
  { name="getEntity",
    select = { "id", "name", "category" }, 
    from = { "entity" } },
  { name="getEntityById",
    select = { "id" }, 
    from = { "entity" },
    where = { "id" } },
  { name="getEntityWithCerts",
    select = { "entity" }, 
    from = { "certificate" } },
  { name="getInterface",
    select = { "repid" },
    from = { "interface" } },
  { name="getAuthorizedInterface",
    select = { "interface.repid" },
    from = { "entityInterface", "interface" },
    where_hc = { "interface.repid = entityInterface.interface" },
    where = { "entityInterface.entity" } },
  { name="getOffer",
    select = { "*" },
    from = { "offer" } },
  { name="getPropertyOffer",
    select = { "*" },
    from = { "propertyOffer" },
    where = { "offer" } },
  { name="getFacet",
    select = { "*" },
    from = { "facet" },
    where = { "offer" } },
  { name="getOfferObserver",
    select = { "*" },
    from = { "offerObserver" },
    where = { "offer" } },
  { name="getOfferRegistryObserver",
    select = { "*" },
    from = { "offerRegistryObserver" },
  },
  { name="getPropertyOfferRegistryObserver",
    select = { "*" },
    from = { "propertyOfferRegistryObserver" },
    where = { "offer_registry_observer" },
  },
  { name="getSettings",
    select = { "value" },
    from = { "settings" },
    where = { "key" }
  },
  { name="getLogin",
    select = { "*" },
    from = { "login" }
  },
  { name="getLoginObserver",
    select = { "*" },
    from = { "loginObserver" }
  },
  { name="getWatchedLoginByObserver",
    select = { "login" },
    from = { "watchedLogin" },
    where = { "login_observer" },
  },
  { name="getAuthorizedInterfaces",
    select = { "interface.repid" },
    from = { "entityInterface", "interface" },
    where_hc = { "interface.repid = entityInterface.interface" },
    where = { "entityInterface.entity" },
  },
}

local emsgprefix = "SQLite error with code="

local function herror(code, extmsg)
  if code and code ~= lsqlite.OK then
    local msg = emsgprefix..tostring(code)
    if extmsg then
      msg = msg.."; "..extmsg  
    end
    return nil, msg
  end
  return true
end

local function gsubSQL(sql)
  return "SQL: [["..string.gsub(sql, '%s+', ' ').."]]"
end

local function iClause(sql, clause, entries, sep, suf)
  if not entries then
    return sql
  end
  if sql then
    sql = sql.." "
  else
    sql = ""
  end
  if not string.find(sql, clause) then 
     sql = sql..clause.." "
  else
     sql = sql.." AND "
  end
  for i, col in ipairs(entries) do
    if i > 1 then sql = sql..sep.." " end
    sql = sql..col
    if suf then sql = sql.." "..suf.." " end
  end
  return sql
end

local function buildSQL(action)
  local name = action.name
  local verb = string.sub(name, 1, 3)
  local sql
  local stable = string.lower(string.sub(name, 4, 4))
     ..string.sub(name, 5, -1)
  if "add" == verb then
    sql = "INSERT INTO "..stable.." ("
    local values = action.values
    sql = sql..table.concat(values, ",")
    sql = sql..") VALUES ("
    sql = sql..string.rep("?", #values, ",")
    sql = sql..")"
  elseif "del" == verb then
    sql = "DELETE FROM "..stable.." "
    sql = iClause(sql, "WHERE", action.where, "AND", "= ?") 
  elseif "set" == verb then
    local stable = action.table or stable
    sql = "UPDATE "..stable.. " "
    sql = sql.."SET "..action.set.. " = ? "
    sql = sql.."WHERE "..action.where.." = ?"
  elseif "get" == verb then
    sql = iClause(nil, "SELECT", action.select, ",")
    local from = action.from
    if from then 
      sql = iClause(sql, "FROM", action.from, ",")
    else
      sql = sql.." FROM "..stable
    end
    sql = iClause(sql, "WHERE", action.where, "AND", "= ?") 
    sql = iClause(sql, "WHERE", action.where_hc, "AND") 
  end
  return sql
end

function DataBase:aexec(sql)
  local gsql = gsubSQL(sql)
  log:database(sql)
  assert(herror(self.conn:exec(sql), gsql))
end

local stmts = {}

function DataBase:__init()
  local conn = self.conn
  self:aexec("BEGIN;")
  self:aexec(SQL_create_tables)
  self:aexec("PRAGMA foreign_keys=ON;")
  local pstmts = {}
  for _, action in ipairs(actions) do
    local sql = buildSQL(action)
    local res, errcode = conn:prepare(sql)
    if not res then 
      assert(herror(errcode, gsubSQL(sql)))
    end
    local key = action.name
    pstmts[key] = res
    stmts[key] = sql
  end
  self:aexec("COMMIT;")
  self.pstmts = pstmts
end

function DataBase:exec(stmt)
  local gsql = gsubSQL(stmt)
  log:database(stmt)
  local res, errmsg = herror(self.conn:exec(stmt))
  errmsg = gsql.." "..emsgprefix..tostring(errcode)
  if errcode == lsqlite.DONE then      
    return true
  elseif errcode == lsqlite.ERROR then
    return nil, errmsg.."; "..self.conn:errmsg()
  end
  return nil, errmsg
end

function DataBase:pexec(action, ...)
  local pstmt = self.pstmts[action]
  local sql = gsubSQL(stmts[action]).." "
  local res, errmsg = herror(pstmt:bind_values(...))
  if not res then
    return nil, sql..errmsg
  end
  local errcode = pstmt:step()
  log:database(sql.." with values {"
  		  ..table.concat({...}, ", ").."}")
  errmsg = sql..emsgprefix..tostring(errcode)
  if errcode == lsqlite.DONE then
    pstmt:reset()
    return true, errcode
  elseif errcode == lsqlite.ROW then
    return true, errcode
  elseif errcode == lsqlite.ERROR then
    errmsg = errmsg.."; "..self.conn:errmsg()
  end  
  return nil, errmsg
end

local module = {}

function module.open(path)
  local conn, errcode, errmsg = lsqlite.open(path)
  if not conn then return herror(errcode, errmsg) end
  return DataBase{ conn = conn }
end

return module
