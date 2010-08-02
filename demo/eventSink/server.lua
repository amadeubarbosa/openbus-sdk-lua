-------------------------------------------------------------------------------
-- Demo de eventos do Servi�o de Sess�o
-- server.lua
--

local oo      = require "loop.base"
local utils   = require ("scs.core.utils").Utils()
local oil     = require "oil"
local openbus = require "openbus.Openbus"
local obUtils = require "openbus.util.Utils"
--oil.verbose:level(5)

-- Carrega as propriedades
local props = {}
utils:readProperties(props, "EventSink.properties")
-- Aliases
local host               = props["host.name"].value
local port               = tonumber(props["host.port"].value)
local entityName         = props["entity.name"].value
local privateKeyFile     = props["private.key"].value
local acsCertificateFile = props["acs.certificate"].value

-- Inicializa��o
openbus:init(host, port)
-- ORB deve estar inicializado antes de carregar o SCS
local scs = require "scs.core.base"

-- Auxiliares
local orb = openbus:getORB()
local compFacet = "IDL:scs/core/IComponent:1.0"
local sinkFacet = "IDL:tecgraf/openbus/session_service/v1_05/SessionEventSink:1.0"
local context

-------------------------------------------------------------------------------
-- Descri��es do componente
local facetDescriptions = {}

facetDescriptions.IComponent = {
  name = "IComponent",
  interface_name = "IDL:scs/core/IComponent:1.0",
  class = scs.Component
}

facetDescriptions.IMetaInterface = {
  name = "IMetaInterface",
  interface_name = "IDL:scs/core/IMetaInterface:1.0",
  class = scs.MetaInterface
}

local componentId = {
  name = "HelloSource",
  major_version = 1,
  minor_version = 0,
  patch_version = 0,
  platform_spec = ""
}

-------------------------------------------------------------------------------
-- Publica os eventos no canal
--
local function publish(session, sink)
  while true do
    oil.sleep(3)
    local num = math.random(1, 10)
    print("Publicando: " .. num)
    local event = {}
    event.type = "LongEvent"
    event.value = setmetatable({ _anyval = num }, oil.corba.idl.long)
    sink:push(event)
  end
end

-- Fun��o principal
local function main ()
  -- Permite que o ORB comece a aguardar requisi��es
  openbus:run()
  -- Instancia��o do componente
  context = scs.newComponent(facetDescriptions, {}, componentId)
  -- Conex�o com o barramento
  local rs = openbus:connectByCertificate(entityName,
    privateKeyFile, acsCertificateFile)
  if not rs then
    io.stderr:write("[ERRO] N�o foi poss�vel conectar ao barramento.\n")
    os.exit(1)
  end
  -- Cria a sess�o
  local sessionService, session, sessionId

  local facets = { obUtils.SESSION_SERVICE_FACET_NAME }
  local offers = rs:find(facets)
  if #offers > 0 then
    local facet = offers[1].member:getFacet(obUtils.SESSION_SERVICE_INTERFACE)
    if not facet then
      io.stderr:write("[ERRO] N�o foi poss�vel obter a faceta do servi�o de sess�o.\n")
    end
    sessionService = orb:narrow(facet, obUtils.SESSION_SERVICE_INTERFACE)
  end

  succ, session, sessionId = sessionService:createSession(context.IComponent)
  if not succ then
    io.stderr:write("[ERRO] N�o foi poss�vel criar sess�o.\n")
    openbus.disconnect()
    openbus.destroy()
    os.exit(1)
  end
  -- Recupera servi�o de eventos
  local comp = orb:narrow(session:_component(), compFacet)
  local sink = orb:narrow(comp:getFacet(sinkFacet), sinkFacet)
  -- Registro do componente
  local registryService = orb:newproxy(rs, "protected") 
  local succ, registryId = registryService:register {
    properties = { 
      {name = "sessionName", value = {"HelloSession"}}, 
      {name = "facets", value ={"IDL:tecgraf/openbus/session_service/v1_05/ISession:1.0"}},
    },
    member = comp,
  }
  if not succ then
    if registryId[1] == "IDL:tecgraf/openbus/core/v1_05/registry_service/UnathorizedFacets:1.0" then
      io.stderr:write("[ERRO] N�o foi poss�vel registrar a oferta.\n")
      for _, facet in ipairs(registryId.facets) do
        io.stderr:write(string.format("[ERRO] Faceta '%s' n�o autorizada.\n", facet))
      end
    else
      io.stderr:write(string.format(
        "[ERRO] N�o foi poss�vel registrar a oferta: %s.\n", registryId[1]))
    end
    openbus:disconnect()
    openbus:destroy()
    os.exit(1)
  end
  -- Publica os eventos
  oil.newthread(publish, session, sink)
  print("[INFO] Publisher ativado.")
end

oil.main(function()
  local succ, msg = oil.pcall(main)
  if not succ then
    print(msg)
  end
end)
