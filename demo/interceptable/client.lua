--
-- OpenBus Demo
-- client.lua
--

local oil = require "oil"
local openbus = require "openbus.Openbus"
local scsutils = require ("scs.core.utils").Utils()
local log = require "openbus.util.Log"

-- Inicializacao do barramento
local props = {}
scsutils:readProperties(props, "Interceptable.properties")
local host = props["host.name"].value
local port = props["host.port"].value
openbus:init(host, tonumber(port))


if arg[1] == "ft" then
  openbus:enableFaultTolerance()
end

--
local orb = openbus:getORB()

-- Execução
function main ()
  -- Carga da IDL Hello
  orb:loadidlfile("idl/hello.idl")

  -- Conexão com o barramento e obtenção do componente HelloComponent
  local login = props.login.value
  local password = props.password.value
  local registryService = openbus:connectByLoginPassword(login, password)
  if not registryService then
    io.stderr:write("HelloClient: Erro ao conectar ao barramento.\n")
    os.exit(1)
  end

  local offers = openbus:getRegistryService():find({"IHello"})

  -- Assume que HelloComponent é o único serviço cadastrado.
  local helloComponent = orb:narrow(offers[1].member,
                      "IDL:scs/core/IComponent:1.0")
  local helloFacet = helloComponent:getFacet("IDL:demoidl/hello/IHello:1.0")
  helloFacet = orb:narrow(helloFacet, "IDL:demoidl/hello/IHello:1.0")

  -- Desconecta antes de chamar o sayHello. Dessa forma, se o metodo estiver
  -- sendo checado, um erro será lançado. O comportamento esperado é que a
  -- chamada funcione normalmente.
  openbus:disconnect()

  helloFacet:sayHello()

  openbus:destroy()
end

oil.main(function()
  print(oil.pcall(main))
end)
