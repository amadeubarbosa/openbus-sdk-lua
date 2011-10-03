cothread = require "cothread"
openbus = require "openbus"

-- connect to the bus
conn = openbus.connectByAddress("localhost", 2089)

-- setup ORB
orb = conn.orb
orb:loadidlfile("messages.idl")

-- login to the bus
conn:loginByPassword("demo", "demo")

-- find the messenger service
offers = conn.offers:findServices({
	{name="offer.domain",value="OpenBus Demos"}, -- provided property
})
assert(#offers == 3, "wrong offered service")
for _, offer in ipairs(offers) do
	local name, iface
	for _, prop in ipairs(offer.properties) do
		if prop.name == "openbus.component.facet" then
			assert(name == nil)
			name = prop.value
		elseif prop.name == "openbus.component.interface" then
			assert(iface == nil)
			iface = prop.value
		end
	end
	_G[name] = orb:narrow(offer.service_ref:getFacet(iface), iface)
end

-- logout from the bus
conn:logout()

conn:loginByPassword("willian", "willian")
forwarder:setForward("bill")
broadcaster:subscribe()
conn:logout()

conn:loginByPassword("paul", "paul")
broadcaster:subscribe()
conn:logout()

conn:loginByPassword("mary", "mary")
broadcaster:subscribe()
conn:logout()

conn:loginByPassword("steve", "steve")
broadcaster:subscribe()
broadcaster:post("Testing the list!")
conn:logout()

io.write("Waiting for messages to propagate ")
for i = 1, 10 do io.write(".") io.flush() cothread.delay(1) end
print(" done!")

function showPostsOf(user, posts)
	print(user.." received "..#posts.." messages:")
	for index, post in ipairs(posts) do
		print(index..") "..post.from..": "..post.message)
	end
	print()
end

for _, user in ipairs{"willian", "bill", "paul", "mary", "steve"} do
	conn:loginByPassword(user, user)
	showPostsOf(user, messenger:receivePosts())
	broadcaster:unsubscribe()
	conn:logout()
end

conn:loginByPassword("willian", "willian")
forwarder:cancelForward("bill")
conn:logout()

conn:close()
