do
	local basedir = "/Users/maia/Work/proj/openbus/draft/full_svn"
	package.path = table.concat({
		basedir.."/openbus/core/trunk/lua/?.lua",
		basedir.."/openbus/core/trunk/test/?.lua",
		basedir.."/openbus/sdk/lua/branches/openbus_v2_proto/lua/?.lua",
		basedir.."/?.lua",
		package.path
	}, ";")
	local loaders = package.loaders
	loaders[2],
	loaders[3],
	loaders[4],
	loaders[5]=
	loaders[3], -- LUA_PATH loader
	loaders[4], -- LUA_CPATH loader
	loaders[5], -- LUA_CPATH bundle loader
	loaders[2]; -- package.preload loader
end

local function cothread_loop()
	_G.lua51_pcall = _G.pcall
	_G.lua51_xpcall = _G.xpcall
	require "coroutine.pcall"
	require "coroutine.debug51"

	local _loadfile = loadfile
	function loadfile(path, mode, env)
		local result, errmsg = _loadfile(path)
		if result ~= nil and env ~= nil then
			setfenv(result, env)
		end
		return result, errmsg
	end

	function string:tag(values)
		return (self:gsub(
			"(%$+)([_%a][_%w]*)",
			function(prefix, field)
				local size = #prefix
				if size%2 == 1 then
					field = tostring(values[field])
				end
				return prefix:sub(1, size/2)..field
			end
		))
	end

	local coroutine = require 'coroutine'
	local cothread = require 'cothread'
	local main = assert(loadfile(arg[1]))
	return cothread.run(cothread.step(coroutine.create(main), unpack(arg, 2)))
end

local function traceback(msg)
	return debug.traceback(tostring(msg))
end
local ok, errmsg = xpcall(cothread_loop, traceback)
if not ok then
	io.stderr:write(arg[0], ": ", errmsg, "\n")
end
