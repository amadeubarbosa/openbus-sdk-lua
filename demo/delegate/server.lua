--
-- OpenBus Delegate Demo
-- server.lua
--

local oil = require "oil"
local oop = require "loop.base"
local openbus = require "openbus.Openbus"
local scsutils = require ("scs.core.utils").Utils()

-- Inicialização do barramento
local props = {}
scsutils:readProperties(props, "Delegate.properties")
local host = props["host.name"].value
local port = props["host.port"].value
openbus:init(host, tonumber(port))
--openbus:enableFaultTolerance()
local orb = openbus:getORB()

local scs = require "scs.core.base"

-- Implementação da Faceta IHello
local Hello = oop.class {}
function Hello:sayHello()
  local intCred = openbus:getInterceptedCredential()
  print "HELLO!\n\n"
  print("[Thread " .. intCred.delegate .. "]: Hello " .. intCred.owner .. " !")
end

-- Descrições do componente HelloComponent
local facetDescriptions = {}
facetDescriptions.IHello = {
  name = "IHello",
  interface_name = "IDL:demoidl/demoDelegate/IHello:1.0",
  class = Hello
}
local componentId = {
  name = "DelegateService",
  major_version = 1,
  minor_version = 0,
  patch_version = 0,
  platform_spec = ""
}

-- Execução
function main ()
  -- Carga da IDL Hello
  orb:loadidlfile("../idl/delegate.idl")

  -- Permite que o ORB comece a aguardar requisições
  openbus:run()

  -- Instanciação do componente HelloComponent
  local component = scs.newComponent(facetDescriptions, {}, componentId)

  -- Conexão com o barramento e registro do componente
  local entityName = props["entity.name"].value
  local privateKeyFile = props["private.key"].value
  local acsCertificateFile = props["acs.certificate"].value
  local registryService = openbus:connectByCertificate(entityName, privateKeyFile, acsCertificateFile)
  if not registryService then
    io.stderr:write("HelloServer: Erro ao conectar ao barramento.\n")
    os.exit(1)
  end
  registryService = orb:newproxy(registryService, "protected")
  local suc, id = registryService:register({ properties = {}, member = component.IComponent})
  if not suc then
    io.stderr:write("HelloServer: Erro ao registrar ofertas.\n")
    if id[1] == "IDL:tecgraf/openbus/core/v1_05/registry_service/UnauthorizedFacets:1.0" then
      for _, facet in ipairs(id.facets) do
        io.stderr:write(string.format("Registro da faceta '%s' não autorizado\n", facet))
      end
    else
      io.stderr:write(string.format("Erro: %s.\n", id[1]))
    end
    os.exit(1)
  end
  print("*********************************************\n")
  print("PUBLISHER\nServiço Hello registrado no barramento do OpenBus.\n")
  print("*********************************************")
end

oil.main(function()
  print(oil.pcall(main))
end)
