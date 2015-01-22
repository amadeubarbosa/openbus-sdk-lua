local _G = require "_G"
local _VERSION = _G._VERSION
local assert = _G.assert
local ipairs = _G.ipairs
local load = _G.load
local loadfile = _G.loadfile
local pcall = _G.pcall
local select = _G.select
local tostring = _G.tostring
local xpcall = _G.xpcall

local array = require "table"
local concat = array.concat

local string = require "string"
local replace = string.gsub
local allmatches = string.gmatch
local match = string.match
local substring = string.sub

local io = require "io"
local readline = io.read
local stderr = io.stderr
local stdout = io.stdout

local os = require "os"
local getenv = os.getenv

local debug = require "debug"
local getregistry = debug.getregistry
local traceback = debug.traceback


local function results(success, ...)
	if success then
		local message = {}
		for i = 1, select("#", ...) do
			message[#message+1] = tostring(select(i, ...))
		end
		return true, concat(message, "\t")
	end
	return nil, tostring(...)
end

local function protectedcall(code, ...)
	local ok, result = xpcall(code, traceback, ...)
	if not ok then return result end
	return nil, result
end

local loaders = {
	code = function (code, env)
		return load(code, "=(command line)", "t", env)
	end,
	module = function (modname, env)
		local result = env.require or require
		return result, modname
	end,
}

local function openconsole(env)
	local lines = {}
	while true do
		if #lines == 0 then
			io.write(_G._PROMPT or "> ")
		else
			io.write(_G._PROMPT2 or ">> ")
		end
		io.flush()
		local result, message = readline()
		if result ~= nil then
			if #lines == 0 then result = replace(result, "^=", "return ") end
			lines[#lines+1] = result
			result, message = load(concat(lines, "\n"), "=stdin", "t", env)
			if result ~= nil then
				lines = {}
				result, message = results(pcall(result))
			elseif match(message, "<eof>$") then
				result, message = true, nil
			else
				lines = {}
			end
		else
			break
		end
		if result == nil or (message and #message > 0) then
			local output = result and stdout or stderr
			output:write(message, "\n")
			output:flush()
		end
	end
end




local module = {}

function module.processargs(env, ignorevars, interactive, executables, script, ...)
	env.arg = {[0]=script, ...}

	local errmsg

	if not ignorevars then
		local name = replace(_VERSION, "Lua (%d+)%.(%d+)", "LUA_INIT_%1_%2")
		local init = getenv(name)
		if init == nil then
			name = "LUA_INIT"
			init = getenv(name)
		end
		if init ~= nil then
			if match(init, "^@") then
				init, errmsg = loadfile(substring(init, 2), "t")
			else
				init, errmsg = load(init, name, "t")
			end
			if init ~= nil then
				errmsg = protectedcall(init)
			end
		end
	else
		getregistry().LUA_NOENV = true -- it is too late for this to work!
	end

	local exitvalue
	if errmsg == nil then
		for _, executable in ipairs(executables) do
			local code, result = loaders[executable.kind](executable.value, env)
			if code == nil then
				errmsg = result
				break
			else
				errmsg, result = protectedcall(code, result)
				if errmsg ~= nil then break end
				if executable.kind == "module" then
					local modname = executable.value
					local place = env
					for name in allmatches(modname, "([^.]+)%.") do
						local table = place[name]
						if table == nil then
							table = {}
							place[name] = table
						end
						place = table
					end
					place[match(modname, "([^.]+)$")] = result
				end
			end
		end

		if errmsg == nil and script ~= nil then
			local code, result = loadfile(script, "t")
			if code == nil then
				errmsg = result
			else
				errmsg, exitvalue = protectedcall(code, ...)
			end
		end
	end

	if errmsg ~= nil then
		stderr:write(tostring(errmsg), "\n")
		return 1
	elseif interactive then
		openconsole(env)
	elseif exitvalue ~= nil then
		return exitvalue
	end
end

return module
