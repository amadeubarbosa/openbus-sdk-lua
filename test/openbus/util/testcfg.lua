local _G = require "_G"
local assert = _G.assert
local io = require "io"
local open = io.open
local os = require "os"
local getenv = os.getenv
local oillog = require "oil.verbose"
local log = require "openbus.util.logger"
local server = require "openbus.util.server"
local readfl = server.readfrom
local setuplog = server.setuplog

propsfile = getenv("OPENBUS_TESTCFG") or "test.properties"
-- TODO: suggest Cadu to do all this in 'scs.core.utils' -----------------------
local props = {getTagOrDefault=function(self, name, default) return default end}
local file = open(propsfile, "r")
if file ~= nil then
  file:close()
  require("scs.core.utils")():readProperties(props, propsfile)
end
-- TODO END --------------------------------------------------------------------
testbase = propsfile:match("^(.-)[^/\\]+$")
setuplog(oillog,       props:getTagOrDefault("oil.verbose.level"   , 0),
                       props:getTagOrDefault("oil.verbose.file"    , ""))
setuplog(log,          props:getTagOrDefault("openbus.log.level"   , 0),
                       props:getTagOrDefault("openbus.log.file"    , ""))
leasetime =            props:getTagOrDefault("login.lease.time"    , 1)
expirationgap =        props:getTagOrDefault("login.expiration.gap", leasetime/2)
buskey =               props:getTagOrDefault("bus.private.key"     , testbase.."openbus.key")
busdb =                props:getTagOrDefault("bus.database"        , testbase.."openbus.db")
bushost =   bushost or props:getTagOrDefault("bus.host.name"       , "localhost")
busport =   busport or props:getTagOrDefault("bus.host.port"       , 2089)
bus2host = bus2host or props:getTagOrDefault("bus2.host.name"      , "localhost")
bus2port = bus2port or props:getTagOrDefault("bus2.host.port"      , 2090)
admin =                props:getTagOrDefault("admin.entity.name"   , "admin")
admpsw =               props:getTagOrDefault("admin.password"      , admin)
user =                 props:getTagOrDefault("user.entity.name"    , "testuser")
password =             props:getTagOrDefault("user.password"       , user)
system =               props:getTagOrDefault("system.entity.name"  , "testsyst")
syskey = assert(readfl(props:getTagOrDefault("system.private.key"  , testbase.."testsyst.key"), "rb"))
syscrt =               props:getTagOrDefault("system.certificate"  , testbase.."testsyst.crt")
category =             props:getTagOrDefault("entity.category.name", "testents")
ldapurl =              props:getTagOrDefault("ldap.url.tcp"        , "ldap://ldap-teste:389")
ldapssl =              props:getTagOrDefault("ldap.url.ssl"        , "ldaps://ldap-teste:636")
ldappat =              props:getTagOrDefault("ldap.pattern"        , "cn=%U,ou=usuarios,dc=tecgraf,dc=puc-rio,dc=br")
ldaptimeout =          props:getTagOrDefault("ldap.timeout"        , 5)
admscript =            props:getTagOrDefault("admin.script.test"   , "testscript.adm")
admoutput =            props:getTagOrDefault("admin.output.file"   , "busadmin.txt")

log:flag("TEST", verbose~=nil)
