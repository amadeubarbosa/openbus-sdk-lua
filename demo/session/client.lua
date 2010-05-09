-------------------------------------------------------------------------------
-- Demo de eventos do Servi�o de Sess�o
-- client.lua
--

local oo      = require "loop.base"
local oil     = require "oil"
local utils   = require ("scs.core.utils").Utils()
local openbus = require "openbus.Openbus"
local OBUtils = require "openbus.util.Utils"

--oil.verbose:level(3)

-- Carrega as propriedades
local props = {}
utils:readProperties(props, "HelloSession.properties")
-- Aliases
local host               = props["host.name"].value
local port               = tonumber(props["host.port"].value)
local login              = props["login"].value
local password           = props["password"].value
local privateKeyFile     = props["private.key"].value
local acsCertificateFile = props["acs.certificate"].value

-- Inicializa��o
openbus:init(host, port)
-- ORB deve estar inicializado antes de carregar o SCS
local scs = require "scs.core.base"

-- Auxiliares
local orb = openbus:getORB()
local compFacet = "IDL:scs/core/IComponent:1.0"
local sessionFacet = "IDL:tecgraf/openbus/session_service/v1_05/ISession:1.0"
local sinkFacet = "IDL:tecgraf/openbus/session_service/v1_05/SessionEventSink:1.0"
local context, sessionId

-------------------------------------------------------------------------------
-- Componente para os eventos
--
local Sink = oo.class{}

function Sink:disconnect()
  -- do nothing
end

function Sink:push(event)
  print("Recebido: " .. event.value._anyval)
end

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

facetDescriptions.SessionEventSink = {
  name = "SessionEventSink",
  interface_name = sinkFacet,
  class = Sink,
}

local componentId = {
  name = "HelloSink",
  major_version = 1,
  minor_version = 0,
  patch_version = 0,
  platform_spec = ""
}

-------------------------------------------------------------------------------
function main ()
  -- Permite que o ORB comece a aguardar requisi��es
  openbus:run()
  -- Instancia��o do componente
  context = scs.newComponent(facetDescriptions, {}, componentId)
  -- Conex�o com o barramento e obten��o do componente de sess�o
  local registryService = openbus:connectByLoginPassword(login, password)
  if not registryService then
    io.stderr:write("[ERRO] N�o foi poss�vel se conectar ao barramento.\n")
    os.exit(1)
  end
  -- Assume que h� s� uma sess�o cadastrada no registro
  -- local offers = registryService:find({"ISession_v" .. OBUtils.OB_VERSION})
  local offers = registryService:findByCriteria({"ISession_v" .. OBUtils.OB_VERSION}, 
                                                { {name = "sessionName", value = {"HelloSession"}} })
  for _, offer in ipairs(offers) do
    local succ = offer.member.__try:_component()
    if succ then
      local component = orb:narrow(offer.member, compFacet)
      component:startup()
      local session = orb:narrow(component:getFacet(sessionFacet), sessionFacet)
      sessionId = session:addMember(context.IComponent)
      return
    end
  end
  io.stderr:write("[ERRO] N�o foi poss�vel localizar sess�o.\n")
  openbus:disconnect()
  openbus:destroy()
  os.exit(1)  
end

oil.main(function()
  local succ, msg = oil.pcall(main)
  if not succ then
    print(msg)
  end
end)
