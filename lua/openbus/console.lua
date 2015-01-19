return function(...)
	local _G = require "_G"
	local _VERSION = _G._VERSION
	local print = _G.print
	local select = _G.select

	local array = require "table"
	local concat = array.concat

	local io = require "io"
	local stderr = io.stderr

	local os = require "os"
	local exit = os.exit

	local Arguments = require "loop.compiler.Arguments"

	local utils = require "openbus.console.utils"
	local processargs = utils.processargs

	local executables = {}

	local args = Arguments{
		i = false,
		v = false,
		E = false,
	}

	function args:e(_, value)
		executables[#executables+1] = {kind="code", value=value}
	end

	function args:l(_, value)
		executables[#executables+1] = {kind="module", value=value}
	end

	local finish = select("#", ...)
	local start, errmsg = args(...)
	if start == nil then
		stderr:write(errmsg, "\n")
		stderr:write([=[
usage: ]=]..OPENBUS_PROGNAME..[=[ [options] [script [args]].
Available options are:
  -e stat  execute string 'stat'
  -i       enter interactive mode after executing 'script'
  -l name  require library 'name'
  -v       show version information
  -E       ignore environment variables
	]=])
		return 1
	end

	if finish == 0 then
		args.i = true
		args.v = true
	end

	if args.v then
		local idl = require "openbus.core.idl"
		local version = concat({
			idl.const.MajorVersion,
			idl.const.MinorVersion,
			0,
			OPENBUS_CODEREV,
		}, ".")
		print("OpenBus "..version.." for ".._VERSION..
		      "  Copyright (C) 2006-2015 Tecgraf, PUC-Rio")
	end

	OPENBUS_EXITCODE = processargs(_ENV, args.E, args.i, executables, select(start, ...))
end
