--
-- OpenBus Demo
-- client.lua
--

local oil = require "oil"
--oil.verbose:level(3)
local openbus = require "openbus.Openbus"
local scsutils = require ("scs.core.utils")()
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

-- Fun��es para diferentes co-rotinas
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

-- Execu��o
function main ()
  -- Carga da IDL Hello
  orb:loadidlfile("idl/delegate.idl")

  -- Conex�o com o barramento (tem de ser por certificado para o delegate) e obten��o do componente HelloComponent
  local entityName = props["entity.name"].value
  local privateKeyFile = props["private.key"].value
  local acsCertificateFile = props["acs.certificate"].value
  local registryService = openbus:connectByCertificate(entityName, privateKeyFile, acsCertificateFile)
  if not registryService then
    io.stderr:write("HelloClient: Erro ao conectar ao barramento.\n")
    os.exit(1)
  end
  local properties = {{name="component_id", value={"DelegateService:1.0.0"}}}
  local offers = registryService:findByCriteria({"IHello"}, properties)

  -- Assume que HelloComponent � o �nico servi�o cadastrado.
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