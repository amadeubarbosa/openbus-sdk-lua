local _G = require "_G"
local assert = _G.assert
local io = require "io"
local open = io.open
local os = require "os"
local getenv = os.getenv
local oillog = require "oil.verbose"
local log = require "openbus.util.logger"
local server = require "openbus.util.server"
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
local function get(...)
  local val = props:getTagOrDefault(...)
  if val ~= "" then return val end
end

testbase = propsfile:match("^(.-)[^/\\]+$")

setuplog(oillog, get("oil.verbose.level"   , 0),
                 get("oil.verbose.file"    , ""))
setuplog(log,    get("openbus.log.level"   , 0),
                 get("openbus.log.file"    , ""))
log:flag("TEST", get("openbus.test.verbose", "no"):lower() == "yes")
leasetime =      get("login.lease.time"    , 1)
expirationgap =  get("login.expiration.gap", leasetime)
bushost =        get("bus.host.name"       , "localhost")
busport =        get("bus.host.port"       , 2089)
busref =         get("bus.reference.path"  , testbase.."BUS01.ior")
buscrt =         get("bus.certificate.path", testbase.."BUS01.crt")
bus2host =       get("bus2.host.name"      , bushost)
bus2port =       get("bus2.host.port"      , busport+1)
bus2ref =        get("bus2.reference.path" , testbase.."BUS02.ior")
bus2crt =        get("bus2.certificate.path",testbase.."BUS02.crt")
admin =          get("admin.entity.name"   , "admin")
admpsw =         get("admin.password"      , admin)
domain =         get("user.password.domain", "testing")
baddomain =      get("bad.password.domain" , "erroneous")
user =           get("user.entity.name"    , "testuser")
password =       get("user.password"       , user)
passwordpenalty= get("password.penalty.time", leasetime)
passwordtries =  get("password.penalty.tries", 3)
system =         get("system.entity.name"  , "testsyst")
syskey =         get("system.private.key"  , testbase.."testsyst.key")
syscrt =         get("system.certificate"  , testbase.."testsyst.crt")
sharedauthfile = get("system.sharedauth"   , testbase.."sharedauth.dat")
category =       get("entity.category.name", "testents")
ldapurl =        get("ldap.url.tcp"        , "ldap://ldap-teste:389")
ldapssl =        get("ldap.url.ssl"        , "ldaps://ldap-teste:636")
ldappat =        get("ldap.pattern"        , "cn=%U,ou=usuarios,dc=tecgraf,dc=puc-rio,dc=br")
ldaptimeout =    get("ldap.timeout"        , 5)
admoutput =      get("admin.output.file"   , "busadmin.txt")

orbsecurity =    get("oil.security.mode")
sslcacrt =       get("ssl.ca.certificate"     , testbase.."testcassl.crt")
sslsyskey =      get("ssl.system.private.key" , testbase.."testsystssl.key")
sslsyscrt =      get("ssl.system.certificate" , testbase.."testsystssl.crt")
sslusrkey =      get("ssl.user.private.key"   , testbase.."testuserssl.key")
sslusrcrt =      get("ssl.user.certificate"   , testbase.."testuserssl.crt")
