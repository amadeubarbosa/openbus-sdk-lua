local autoprops = {
  "openbus.offer.id",
  "openbus.offer.login",
  "openbus.offer.entity",
  "openbus.offer.timestamp",
  "openbus.offer.year",
  "openbus.offer.month",
  "openbus.offer.day",
  "openbus.offer.hour",
  "openbus.offer.minute",
  "openbus.offer.second",
  "openbus.component.name",
  "openbus.component.version.major",
  "openbus.component.version.minor",
  "openbus.component.version.patch",
  "openbus.component.facet",
  "openbus.component.interface",
}
local function assertlocalprops(assistant, expected, actual)
  local currentlogin = assistant.login
  local actualprops = actual:describe().properties
  for _, property in ipairs(expected.properties) do
    assert(assistant.getProperty(properites, property.name) == property.value)
  end
  for _, propname in ipairs(autoprops) do
    if currentlogin then
      assert(assistant.getProperty(properties, name) ~= nil)
    else
      assert(assistant.getProperty(properties, name) == nil)
    end
  end
end

local offer = assistant:registerService(offers[1].component, offers[1].properties)
assertlocalprops(offer:describe().properties, offers[1].properties, true)
offer:setProperties(offers[1].newprops)
assertlocalprops(offer:describe().properties, offers[1].newprops, true)

sleep(1)

assertlocalprops(offer:describe().properties, offers[1].newprops)
offer:setProperties(offers[1].properties)
assertlocalprops(offer:describe().properties, offers[1].properties)
