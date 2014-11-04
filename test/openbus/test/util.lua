local array = require "table"
local msg = require "openbus.util.messages"
local server = require "openbus.util.server"
local openbus = require "openbus"

require "openbus.test.configs"

function settestcfg(interface, testname)
  local name = interface.name:lower()
  if name == "hello" then name = "server" end
  local language = "lua"
  local domain = "interop_"..testname
  system = domain.."_"..language.."_"..name
  user = domain.."_"..language.."_client"
  password = user
  properties = {{name="offer.domain",value="Interoperability Tests"}}
end

function chain2str(chain)
  local entities = {}
  for index, login in ipairs(chain.originators) do
    entities[index] = login.entity
  end
  entities[#entities+1] = chain.caller.entity
  return array.concat(entities, "->")
end

function getprop(properties, name)
  for _, prop in ipairs(properties) do
    if prop.name == name then return prop.value end
  end
end

function findoffers(offers, props, count, tries, interval)
  if count == nil then count = 1 end
  if tries == nil then tries = 10 end
  if interval == nil then interval = 1 end
  local found = {}
  for i = 1, tries do
    local offers = offers:findServices(props)
    for _, offer in ipairs(offers) do
      local service = offer.service_ref
      local ok, ne = pcall(service._non_existent, service)
      if ok and not ne then
        found[#found+1] = offer
      end
    end
    if #found >= count then return found end
    found = {}
    openbus.sleep(interval)
  end
  error(msg.UnableToFindOffers:tag{
    actual = #found,
    expected = count,
    tries = tries,
    time = tries*interval,
  })
end

function waitfile(path, tries, interval)
  if tries == nil then tries = 10 end
  if interval == nil then interval = 1 end
  for i = 1, tries do
    local data = server.readfrom(path, "rb")
    if data ~= nil then
      os.remove(path)
      return data
    end
    openbus.sleep(interval)
  end
  error(msg.UnableToFindFile:tag{
    tries = tries,
    time = tries*interval,
  })
end
