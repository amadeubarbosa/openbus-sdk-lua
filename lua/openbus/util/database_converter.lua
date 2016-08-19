
local db = require "openbus.util.database"
local dblegacy = require "openbus.util.database_legacy"

local module = {}

local function bool2int(val)
  return (val and 1) or 0
end

function module.convert(dblegacy, db)
  db.conn:exec("BEGIN;")
  local certificateDB = dblegacy:gettable("Certificates")
  for entity in certificateDB:ientries() do
    local certificate = certificateDB:getentry(entity)
    assert(db:pexec("addCertificate", certificate, entity))    
  end

  local autosets = dblegacy:gettable("AutoSetttings")
  local busid = autosets:getentry("BusId")
  if busid then
    assert(db:pexec("addSettings", "BusId", busid))
  end

  local loginsDB = dblegacy:gettable("Logins")
  for id, data in loginsDB:ientries() do
    assert(db:pexec("addLogin", id, data.entity, data.encodedkey,
		    bool2int(data.allowLegacyDelegate)))
  end

  local loginobsDB = dblegacy:gettable("LoginObservers")
  for id, data in loginobsDB:ientries() do
    assert(db:pexec("addLoginObserver", id, data.ior, bool2int(data.legacy),
		    data.login))
    for login in pairs(data.watched) do
      assert(db:pexec("addWatchedLogin", id, login))
    end
  end

  local interfaceDB = dblegacy:gettable("Interfaces")
  for _, ifaceId in interfaceDB:ientries() do
    assert(db:pexec("addInterface", ifaceId))    
  end

  local categoryDB = dblegacy:gettable("Categories")
  for id, name in categoryDB:ientries() do
    assert(db:pexec("addCategory", id, name))
  end  

  local entityDB = dblegacy:gettable("Entities")
  for id, entry in entityDB:ientries() do
    assert(db:pexec("addEntity", id, entry.name, entry.categoryId))
    if entry.authorized then
      for repid in pairs(entry.authorized) do
        assert(db:pexec("addEntityInterface", id, repid))
      end
    end
  end

  local offerDB = dblegacy:gettable("Offers")
  for id, entry in offerDB:ientries() do
    assert(db:pexec("addOffer",
		    id,
		    entry.service_ref,
		    entry.entity,
		    entry.login,
		    entry.creation.timestamp,
		    entry.creation.day,
		    entry.creation.month,
		    entry.creation.year,
		    entry.creation.hour,
		    entry.creation.minute,
		    entry.creation.second,
		    entry.component.name,
		    tostring(entry.component.major_version),
		    tostring(entry.component.minor_version),
		    tostring(entry.component.patch_version),
		    entry.component.platform_spec
    ))
    for _, property in ipairs(entry.properties) do
      assert(db:pexec("addPropertyOffer", property.name, property.value, id))
    end
    for _, facet in ipairs(entry.facets) do
      assert(db:pexec("addFacet", facet.name, facet.interface_name, id))
    end
    for observer_id, entry in pairs(entry.observers) do
      assert(db:pexec("addOfferObserver", observer_id, entry.login,
		      entry.observer, id))
    end
  end
  
  local offerRegObsDB = dblegacy:gettable("OfferRegistryObservers")
  for id, entry in offerRegObsDB:ientries() do
    assert(db:pexec("addOfferRegistryObserver", id, entry.login,
		    entry.observer))
    for _, property in ipairs(entry.properties) do
      assert(db:pexec("addPropertyOfferRegistryObserver",
        property.name, property.value, id))
    end
  end
  db.conn:exec("COMMIT;")
end

return module
