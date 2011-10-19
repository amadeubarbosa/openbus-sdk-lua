-- $Id $

local Verbose = require "loop.debug.Verbose"
local Viewer = require "loop.debug.Viewer"
local oilverbose = require "oil.verbose"

local log = Verbose{
	showthread = true,
	timed = true,
	viewer = Viewer {      -- define forma que valores Lua são exibidos
		maxdepth = 2,        -- nível de profundidade que tabelas são exibidas
		indentation = "|  ", -- indentação usada na exibição de tabelas
		noindices = true,
		labels = oilverbose.viewer.labels
	},
	groups = {
		{"error"},  -- erros lançados durante a execução do serviço
		{"warn"},   -- condições adversas encontradas, mas que são ignoradas
		{"info"},   -- informações de depuração para o adminstrador
		{"debug"},  -- informações de depuração para usuários do serviço
		{"extra"},
		
		error = { "unexpected", "failure" },
		warn = { "exception", "misconfig" },
		info = { "config", "admin", "uptime" },
		debug = { "request", "action" },
		extra = { "access", "badaccess", "multiplexed" },
	},
}
log:settimeformat("%d/%m/%Y %H:%M:%S") -- inclui data e hora no log
log:flag("print", true)
return log
