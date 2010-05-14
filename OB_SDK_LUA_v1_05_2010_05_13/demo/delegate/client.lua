--
-- OpenBus Demo
-- client.lua
--

local oil = require "oil"
--oil.verbose:level(3)
local openbus = require "openbus.Openbus"
local scsutils = require ("scs.core.utils").Utils()
local log = require "openbus.util.Log"

-- Inicializacao do barramento
local props = {}
scsutils:readProperties(props, "Delegate.properties")
local host = props["host.name"].value
local port = props["host.port"].value
openbus:init(host, tonumber(port))
--openbus:enableFaultTolerance()
local orb = openbus:getORB()

local finished = {A = false, B = false}

-- Funções para diferentes co-rotinas
function delegate(helloObj, name)
  local cred = openbus:getCredential()
  local newCred = {identifier = cred.identifier, owner = cred.owner, 
                     delegate = name}
  openbus:setThreadCredential(newCred)
  local status, err
  for i=0,10 do
    status, err = oil.pcall(helloObj.sayHello, helloObj, name)
    if not status then
      print("HelloClient: Erro na chamada sayHello pela 'thread' "..name..".")
      break
    end
    oil.sleep(1)
  end
  finished[name] = true
end

-- Execução
function main ()
  -- Carga da IDL Hello
  orb:loadidlfile("../idl/delegate.idl")

  -- Conexão com o barramento e obtenção do componente HelloComponent
  local login = props.login.value
  local password = props.password.value
  local registryService = openbus:connectByLoginPassword(login, password)
  if not registryService then
    io.stderr:write("HelloClient: Erro ao conectar ao barramento.\n")
    os.exit(1)
  end
  local properties = {{name="component_id", value={"DelegateService:1.0.0"}}}
  local offers = registryService:findByCriteria({"IHello"}, properties)

  -- Assume que HelloComponent é o único serviço cadastrado.
  local helloComponent = orb:narrow(offers[1].member,
    "IDL:scs/core/IComponent:1.0")
  local helloFacet = helloComponent:getFacet("IDL:demoidl/demoDelegate/IHello:1.0")
  helloFacet = orb:narrow(helloFacet, "IDL:demoidl/demoDelegate/IHello:1.0")

  oil.newthread(delegate, helloFacet, "A")
  oil.newthread(delegate, helloFacet, "B")

  while true do
    if finished["A"] and finished["B"] then
      break
    else
      oil.sleep(1)
    end
  end

  openbus:disconnect()
  openbus:destroy()
end

oil.main(function()
  print(oil.pcall(main))
end)
