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

	local extra = ""

	if preload.lpw ~= nil then
		extra = [[
			["*?"] = require("lpw").getpass,
		]]
	end

	spawn([[
		local io = require "io"
		local readline = io.read
		local cothread = require "cothread"
		cothread.plugin(require "cothread.plugin.socket")
		local socket = require "cothread.socket"
		local newsocket = socket.tcp

		local Message = "%d\n%s"
		local handlers = {
			]]..extra..[[
		}

		local sock = newsocket()
		assert(sock:connect("localhost", ]]..port..[[))

		while true do
			local format = sock:receive()
			if format ~= nil then
				local handler = handlers[format]
				if handler ~= nil then
					result = handler()
				else
					result = readline(format)
				end
				assert(sock:send(#result.."\n"..result))
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
				conn:send(tostring(format).."\n")
				local size = tonumber(conn:receive())
				results[index] = size == 0 and "" or conn:receive(size)
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
