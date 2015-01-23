return function (...)
	local _G = require "_G"
	local assert = _G.assert
	local ipairs = _G.ipairs
	local select = _G.select
	local tonumber = _G.tonumber
	local tostring = _G.tostring

	local package = require "package"
	local preload = package.preload

	local array = require "table"
	local unpack = array.unpack

	local io = require "io"

	local Wrapper = require "loop.object.Wrapper"

	local cothread = require "cothread"
	cothread.plugin(require "cothread.plugin.socket")
	local socket = require "cothread.socket"
	local newsocket = socket.tcp
	local Mutex = require "cothread.Mutex"

	local thread = require "openbus.util.thread"
	local spawn = thread.spawn

	local ValidFormats = {
		["*n"] = true,
		["*a"] = true,
		["*l"] = true,
		["*L"] = true,
		["*?"] = true,
	}

	local sock = assert(newsocket())
	assert(sock:bind("127.0.0.1", 0))
	local _, port = assert(sock:getsockname())
	assert(sock:listen())

	spawn([[
		local io = require "io"
		local readline = io.read
		local writetext = io.write

		local cothread = require "cothread"
		cothread.plugin(require "cothread.plugin.socket")
		local socket = require "cothread.socket"
		local newsocket = socket.tcp

		local echo = require "openbus.util.echo"
		local getecho = echo.getecho
		local setecho = echo.setecho

		local Message = "%d\n%s"
		local handlers = {
			["*?"] = function()
				local active = getecho()
				if active then setecho(false) end
				result = readline()
				if active then setecho(true) end
				writetext("\n")
				return result
			end,
		}

		local sock = newsocket()
		assert(sock:connect("localhost", ]]..port..[[))

		while true do
			local format = sock:receive()
			if format ~= nil then
				local ok, result = pcall(handlers[format] or readline, format)
				assert(sock:send((ok and "." or "!")..#result.."\n"..result))
			else
				assert(sock:close())
				break
			end
		end
	]])
	local conn = assert(sock:accept())
	assert(sock:close())

	local stdin = io.stdin
	local mutex = Mutex()
	local RemoteStdIn = Wrapper{ __object = stdin }

	function RemoteStdIn:read(...)
		local results = {}
		for index = 1, select("#", ...) do
			local format = select(index, ...)
			assert(ValidFormats[format] or tonumber(format), "illegal format")
			results[index] = format
		end
		if #results == 0 then results[1] = "*l" end
		if mutex:try() then
			for index, format in ipairs(results) do
				assert(conn:send(tostring(format).."\n"))
				local ok = (assert(conn:receive(1)) == ".")
				local size = assert(tonumber(assert(conn:receive())))
				local result = (size == 0) and "" or assert(conn:receive(size))
				if not ok then
					mutex:free()
					error(result)
				end
				results[index] = result
			end
			mutex:free()
			return unpack(results)
		end
		return nil, "denied by other thread"
	end

	local inactive = false
	if stdin ~= nil then
		io.stdin = RemoteStdIn
	end
	local stdread = io.read
	if stdread ~= nil then
		function io.read(...)
			if not inactive then
				return RemoteStdIn:read(...)
			end
			return stdread(...)
		end
	end
	local stdinput = io.input
	if stdinput ~= nil then
		function io.input(file)
			local wasinactive = inactive
			inactive = file ~= RemoteStdIn
			if wasinactive then
				if inactive then
					return stdinput(file)
				else
					return stdinput(stdin)
				end
			end
			return RemoteStdIn
		end
	end
end
