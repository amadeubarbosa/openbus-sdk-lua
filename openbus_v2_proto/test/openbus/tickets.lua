TicketHistory = require "openbus.util.tickets"

local function checkAdd(h, id, smallest, ...)
	--io.write(id,": ",h:__tostring()," ---> ")
	assert(h:check(id) == true, id.." appeared before")
	for id = 1, smallest do
		assert(h:check(id) == false, id.." was not remembered")
	end
	for i = 1, select("#", ...) do
		local id = select(i, ...)
		assert(h:check(id) == false, id.." was not remembered")
	end
	--io.write(h:__tostring(),"\n")
end

do
	local h = TicketHistory{size=4}
	checkAdd(h, 0, 0)
	checkAdd(h, 2, 0, 2)
	checkAdd(h, 4, 0, 2, 4)
	checkAdd(h, 1, 2, 4)
	checkAdd(h, 3, 4)
	checkAdd(h, 10, 5, 10) -- 5 was forgotten
	checkAdd(h, 8, 5, 8, 10)
	checkAdd(h, 9, 5, 8, 9, 10)
	checkAdd(h, 7, 5, 7, 8, 9, 10)
	checkAdd(h, 6, 10)
end

do
	local h = TicketHistory{size=4}
	checkAdd(h, 0, 0)
	checkAdd(h, 2, 0, 2)
	checkAdd(h, 4, 0, 2, 4)
	checkAdd(h, 1, 2, 4)
	checkAdd(h, 3, 4)
	checkAdd(h, 6, 4, 6)
	checkAdd(h, 10, 6, 10) -- 5 was forgotten
	checkAdd(h, 8, 6, 8, 10)
	checkAdd(h, 9, 6, 8, 9, 10)
	checkAdd(h, 7, 10)
end

do
	local h = TicketHistory{size=4}
	checkAdd(h, 0, 0)
	checkAdd(h, 3, 0, 3)
	checkAdd(h, 1, 1, 3)
	checkAdd(h, 2, 3)
	checkAdd(h, 5, 3, 5)
	checkAdd(h, 4, 5)
	checkAdd(h, 300, 295, 300) -- 6 to 295 are forgotten
	checkAdd(h, 296, 296, 300)
	checkAdd(h, 297, 297, 300)
	checkAdd(h, 298, 298, 300)
	checkAdd(h, 299, 300)
end

do
	local h = TicketHistory{size=4}
	checkAdd(h, 0, 0)
	checkAdd(h, 3, 0, 3)
	checkAdd(h, 2, 0, 2, 3)
	checkAdd(h, 5, 0, 2, 3, 5)
	checkAdd(h, 4, 0, 2, 3, 4, 5)
	checkAdd(h, 300, 295, 300) -- 6 to 295 are forgotten
	checkAdd(h, 296, 296, 300)
	checkAdd(h, 297, 297, 300)
	checkAdd(h, 298, 298, 300)
	checkAdd(h, 299, 300)
end

do
	local h = TicketHistory{size=4}
	checkAdd(h, 0, 0)
	checkAdd(h, 3, 0, 3)
	checkAdd(h, 2, 0, 2, 3)
	checkAdd(h, 5, 0, 2, 3, 5)
	checkAdd(h, 4, 0, 2, 3, 4, 5)
	checkAdd(h, 6, 6) -- 1 was fogotten
end
