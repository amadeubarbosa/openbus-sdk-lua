--
-- OpenBus Demo
-- server.lua
--

local oil = require "oil"
local oop = require "loop.base"
local openbus = require "openbus.Openbus"
local Utils = require "openbus.util.Utils"
local ComponentContext = require "scs.core.ComponentContext"
local scsutils = require ("scs.core.utils")()

-- Inicializa��o do barramento
local props = {}
scsutils:readProperties(props, "Hello.properties")
local host = props["host.name"].value
local port = props["host.port"].value
openbus:init(host, tonumber(port))

if arg[1] == "ft" then
  openbus:enableFaultTolerance()
end

local orb = openbus:getORB()

-- Implementa��o da Faceta IHello
local Hello = oop.class {}
function Hello:sayHello()
  local user = openbus:getInterceptedCredential().owner
  print "HELLO!\n\n"
  print("O usu�rio OpenBus " .. user .. " requisitou a opera��o sayHello.")
end

-- Execu��o
function main ()
  -- Carga da IDL Hello
  orb:loadidlfile("../idl/hello.idl")

  -- Permite que o ORB comece a aguardar requisi��es
  openbus:run()

  -- Instancia��o do componente HelloComponent
  local componentId = {
    name = "HelloComponent",
    major_version = 1,
    minor_version = 0,
    patch_version = 0,
    platform_spec = ""
  }

  local component = ComponentContext(orb, componentId)
  component:addFacet("IHello", "IDL:demoidl/hello/IHello:1.0", Hello())

  -- Conex�o com o barramento e registro do componente
  local entityName = props["entity.name"].value
  local privateKeyFile = props["private.key"].value
  local acsCertificateFile = props["acs.certificate"].value
  local registryService = openbus:connectByCertificate(entityName, privateKeyFile, acsCertificateFile)
  if not registryService then
    io.stderr:write("HelloServer: Erro ao conectar ao barramento.\n")
    os.exit(1)
  end
  registryService = orb:newproxy(registryService, "protected", Utils.REGISTRY_SERVICE_INTERFACE)
  local suc, id = registryService:register({
    member = component.IComponent,
    properties = {
      { name = "facets", value = {"IDL:demoidl/hello/IHello:1.0",} }
    },
  })
  if not suc then
      io.stderr:write("HelloServer: Erro ao registrar ofertas.\n")
      if id[1] == "IDL:tecgraf/openbus/core/v1_05/registry_service/UnathorizedFacets:1.0" then
        for _, facet in ipairs(id.facets) do
          io.stderr:write(string.format("Registro da faceta '%s' n�o autorizado\n", facet))
        end
      else
        io.stderr:write(string.format("Erro: %s.\n", id[1]))
      end
      os.exit(1)
  end
  print("*********************************************\n")
  print("PUBLISHER\nServi�o Hello registrado no barramento do OpenBus.\n")
  print("*********************************************")
end

oil.main(function()
  print(oil.pcall(main))
end)
