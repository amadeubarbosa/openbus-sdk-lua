-------------------------------------------------------------------------------
-- Demo de eventos do Servi�o de Sess�o
-- client.lua
--

local oo      = require "loop.base"
local oil     = require "oil"
local utils   = require ("scs.core.utils")()
local openbus = require "openbus.Openbus"
local OBUtils = require "openbus.util.Utils"
local ComponentContext = require "scs.core.ComponentContext"
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

-- Inicializa��o
openbus:init(host, port)

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
function main ()
  -- Carga da DL do Servi�o de Sess�o
  local IDLPATH_DIR = os.getenv("IDLPATH_DIR")
  local idlfile = IDLPATH_DIR .. "/".. OBUtils.IDL_VERSION.."/session_service.idl"
  orb:loadidlfile(idlfile)

  -- Permite que o ORB comece a aguardar requisi��es
  openbus:run()

  -- Instancia��o do componente
  local componentId = {
    name = "HelloSink",
    major_version = 1,
    minor_version = 0,
    patch_version = 0,
    platform_spec = ""
  }

  context = ComponentContext(orb, componentId)
  context:putFacet("SessionEventSink", sinkFacet, Sink())

  -- Conex�o com o barramento e obten��o do componente de sess�o
  local registryService = openbus:connectByLoginPassword(login, password)
  if not registryService then
    io.stderr:write("[ERRO] N�o foi poss�vel se conectar ao barramento.\n")
    os.exit(1)
  end
  -- Assume que h� s� uma sess�o cadastrada no registro
  -- local offers = registryService:find({"ISession_v" .. OBUtils.IDL_VERSION})
  local offers = registryService:findByCriteria({"ISession_" .. OBUtils.IDL_VERSION}, 
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
