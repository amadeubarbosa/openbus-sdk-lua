-- $Id $

local Verbose = require "loop.debug.Verbose"
local Viewer = require "loop.debug.Viewer"
local oillog = require "oil.verbose"

oillog.showthread = true
oillog.timed = true
oillog:settimeformat("%d/%m/%Y %H:%M:%S") -- inclui data e hora no log do OiL

local log = Verbose{
  timed = true,
  viewer = Viewer{
    maxdepth = 2,
    labels = oillog.viewer.labels,
  },
  groups = {
    {"version","error"},-- erros lançados durante a execução do serviço
    {"warn"},           -- condições adversas encontradas, mas que são ignoradas
    {"info"},           -- informações de depuração para o adminstrador
    {"debug"},          -- informações de depuração para usuários do serviço
    {"extra"},
    {"multiplex"},
    
    error = { "unexpected", "failure" },
    warn = { "exception", "misconfig" },
    info = { "config", "admin", "uptime" },
    debug = { "request", "action" },
    extra = { "access", "badaccess" },
    
    DEBUG = { "LOGIN_CACHE" } -- TODO:[maia] to be removed after all tests
  },
}
log:settimeformat("%d/%m/%Y %H:%M:%S") -- inclui data e hora no log
log:flag("print", true)
return log
