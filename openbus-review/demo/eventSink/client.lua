-------------------------------------------------------------------------------
-- Demo de eventos do Serviço de Sessão
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
utils:readProperties(props, "EventSink.properties")
-- Aliases
local host               = props["host.name"].value
local port               = tonumber(props["host.port"].value)
local login              = props["login"].value
local password           = props["password"].value
local privateKeyFile     = props["private.key"].value
local acsCertificateFile = props["acs.certificate"].value

-- Inicialização
openbus:init(host, port)
-- ORB deve estar inicializado antes de carregar o SCS
local scs = require "scs.core.base"

-- Auxiliares
local orb = openbus:getORB()
local compFacet = OBUtils.COMPONENT_INTERFACE
local sessionFacet = OBUtils.SESSION_INTERFACE
local sinkFacet = OBUtils.SESSION_ES_INTERFACE
local context, sessionId

-------------------------------------------------------------------------------
-- Componente para os eventos
--
local Sink = oo.class{}

function Sink:disconnect()
  -- do nothing
end

function Sink:push(identifier, event)
  print("Recebido: " .. event.value._anyval)
end

-------------------------------------------------------------------------------
-- Descrições do componente
local facetDescriptions = {}

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
  -- Carga da IDL do Serviço de Sessão
  local IDLPATH_DIR = os.getenv("IDLPATH_DIR")
  local idlfile = IDLPATH_DIR .. "/".. OBUtils.OB_VERSION.."/session_service.idl"
  orb:loadidlfile(idlfile)

  -- Permite que o ORB comece a aguardar requisições
  openbus:run()
  -- Instanciação do componente
  context = scs.newComponent(facetDescriptions, {}, componentId)
  -- Conexão com o barramento e obtenção do componente de sessão
  local registryService = openbus:connectByLoginPassword(login, password)
  if not registryService then
    io.stderr:write("[ERRO] Não foi possível se conectar ao barramento.\n")
    os.exit(1)
  end
  -- Assume que há só uma sessão cadastrada no registro
  -- local offers = registryService:find({"ISession_v" .. OBUtils.OB_VERSION})
  local offers = registryService:findByCriteria({"ISession_" .. OBUtils.OB_VERSION}, 
                                                { {name = "sessionName", value = {"HelloSession"}} })
  for _, offer in ipairs(offers) do
    local member = orb:newproxy(offer.member, "protected")
    local succ = member:_component()
    if succ then
      local component = orb:narrow(offer.member, compFacet)
      local session = orb:narrow(component:getFacet(sessionFacet), sessionFacet)
      sessionId = session:addMember(context.IComponent)
      return
    end
  end
  io.stderr:write("[ERRO] Não foi possível localizar sessão.\n")
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
