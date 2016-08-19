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
    {"version","error"},-- erros lançados durante a execução do serviço
    {"warn"},           -- condições adversas encontradas, mas que são ignoradas
    {"info"},           -- informações de depuração para o adminstrador
    {"debug"},          -- informações de depuração para usuários do serviço
    {"access"},         -- informações sobre as chamadas interceptadas
    {"multiplex"},      -- informações sobre logins utilizados nas chamadas
    {"database"},
    
    error = {
      "unexpected", -- unexpected errors, usually indicates a bug.
      "failure",    -- exceptions caused by problems in the service itself.
    },
    warn = {
      "exception",  -- exceptions caused by problems in the requests received.
      "misconfig",  -- errors of the service configuration that are ignored.
    },
    info = {
      "config",     -- information about the service configuration parameters.
      "admin",      -- requests performed that are exclusive to admin users.
      "uptime",     -- startup and shutdown of the service and other life cycle
                    -- events.
    },
    debug = {
      "request",    -- changes of the state of the service as a result of a
                    -- external request, like a remote operation.
      "action",     -- changes of the state of the service initiated by the
                    -- service itself, like some auto-cleaning.
    },
  },
}
log:settimeformat(TimeFormat) -- inclui data e hora no log
log:flag("print", true)
return log
