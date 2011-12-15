local string = require "string.bitwise"
local large = 10000
local op1 = "\000\255\000\255\085"
local op2 = "\000\255\255\000\170"
local res = {
	bnot = "\255\000\255\000\170",
	band = "\000\255\000\000\000",
	bor  = "\000\255\255\255\255",
	bxor = "\000\000\255\255\255",
}
for op, res in pairs(res) do
	op = string[op]
	assert(op(op1, op2) == res)
	assert(op(op1:rep(large), op2:rep(large)) == res:rep(large))
	assert(op("", "") == "")
	if op ~= string.bnot then
		local ok, err = pcall(op, "123", "1234")
		assert(ok == false)
		assert(err:match("bad argument #2 to '.-' %(must be the same length of argument #1%)$"))
	end
end
