-- $Id $

local Verbose = require "loop.debug.Verbose"
local Viewer = require "loop.debug.Viewer"
local oilverbose = require "oil.verbose"

local log = Verbose{
	showthread = true,
	timed = true,
	viewer = Viewer {      -- define forma que valores Lua s�o exibidos
		maxdepth = 2,        -- n�vel de profundidade que tabelas s�o exibidas
		indentation = "|  ", -- indenta��o usada na exibi��o de tabelas
		noindices = true,
		labels = oilverbose.viewer.labels
	},
	groups = {
		{"error"},  -- erros lan�ados durante a execu��o do servi�o
		{"warn"},   -- condi��es adversas encontradas, mas que s�o ignoradas
		{"info"},   -- informa��es de depura��o para o adminstrador
		{"debug"},  -- informa��es de depura��o para usu�rios do servi�o
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
