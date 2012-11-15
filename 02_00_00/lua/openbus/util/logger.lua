-- $Id $

local Verbose = require "loop.debug.Verbose"
local Viewer = require "loop.debug.Viewer"
local oillog = require "oil.verbose"

local TimeFormat = "%d/%m/%Y %H:%M:%S"

oillog.showthread = true
oillog.timed = true
oillog:settimeformat(TimeFormat) -- inclui data e hora no log do OiL

local log = Verbose{
  timed = true,
  viewer = Viewer{
    maxdepth = 2,
    labels = oillog.viewer.labels,
  },
  groups = {
    {"version","error"},-- erros lan�ados durante a execu��o do servi�o
    {"warn"},           -- condi��es adversas encontradas, mas que s�o ignoradas
    {"info"},           -- informa��es de depura��o para o adminstrador
    {"debug"},          -- informa��es de depura��o para usu�rios do servi�o
    {"access"},
    {"multiplex"},
    
    error = { "unexpected", "failure" },
    warn = { "exception", "misconfig" },
    info = { "config", "admin", "uptime" },
    debug = { "request", "action" },
  },
}
log:settimeformat(TimeFormat) -- inclui data e hora no log
log:flag("print", true)
return log
