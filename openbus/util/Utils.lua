-- $Id: $

local type     = type
local print    = print
local pairs    = pairs
local ipairs   = ipairs
local tostring = tostring
local assert   = assert
local unpack   = unpack
local error    = error
local format   = string.format

local os     = os
local string = string
local table  = table
local io       = io

local oil = require "oil"

local oop = require "loop.base"
local Viewer = require "loop.debug.Viewer"

local Log = require "openbus.util.Log"
local OilUtilities = require "openbus.util.OilUtilities"


---
-- API utilitária.
---
module "openbus.util.Utils"

---
-- Versao atual do OpenBus
---
OB_VERSION = "v1_06"

---
-- Versao anterior do OpenBus
---
OB_PREV = "v1_05"

---
--  A interface IAccessControlService.
---
ACCESS_CONTROL_SERVICE_INTERFACE = "IDL:tecgraf/openbus/core/"..OB_VERSION..
    "/access_control_service/IAccessControlService:1.0"

---
--  A interface IAccessControlService utilizada na versão anterior.
---
ACCESS_CONTROL_SERVICE_INTERFACE_PREV = "IDL:tecgraf/openbus/core/"..OB_PREV..
    "/access_control_service/IAccessControlService:1.0"

---
--  A interface ILeaseProvider.
---
LEASE_PROVIDER_INTERFACE = "IDL:tecgraf/openbus/core/" .. OB_VERSION ..
    "/access_control_service/ILeaseProvider:1.0"

---
--  A interface ILeaseProvider utilizada na versão anterior.
---
LEASE_PROVIDER_INTERFACE_PREV = "IDL:tecgraf/openbus/core/"..OB_PREV..
    "/access_control_service/ILeaseProvider:1.0"

---
--  A interface IFaultTolerantService.
---
FAULT_TOLERANT_SERVICE_INTERFACE =
  "IDL:tecgraf/openbus/fault_tolerance/" .. OB_VERSION ..
    "/IFaultTolerantService:1.0"

---
--  A interface IFTServiceMonitor.
---
FT_SERVICE_MONITOR_INTERFACE =
  "IDL:tecgraf/openbus/fault_tolerance/" .. OB_VERSION ..
    "/IFTServiceMonitor:1.0"

---
--  A interface IComponent.
---
COMPONENT_INTERFACE =
  "IDL:scs/core/IComponent:1.0"

METAINTERFACE_INTERFACE = "IDL:scs/core/IMetaInterface:1.0"

---
----  A interface IReceptacles.
-----
--
RECEPTACLES_INTERFACE =
  "IDL:scs/core/IReceptacles:1.0"



---
--  A interface IRegistryService.
---
REGISTRY_SERVICE_INTERFACE = "IDL:tecgraf/openbus/core/"..OB_VERSION..
    "/registry_service/IRegistryService:1.0"

---
--  A interface IRegistryService utilizada na versão anterior.
---
REGISTRY_SERVICE_INTERFACE_PREV = "IDL:tecgraf/openbus/core/"..OB_PREV..
    "/registry_service/IRegistryService:1.0"

---
--  A chave para obtenção do barramento.
---
OPENBUS_KEY = "openbus_" .. OB_VERSION

---
--  As chaves CORBALOC para obtenção das interfaces do ACS.
---
ACCESS_CONTROL_SERVICE_KEY = "ACS_"..OB_VERSION
ACCESS_CONTROL_SERVICE_KEY_PREV = "ACS_"..OB_PREV
LEASE_PROVIDER_KEY = "LP_"..OB_VERSION
LEASE_PROVIDER_KEY_PREV = "LP_"..OB_PREV
FAULT_TOLERANT_ACS_KEY = "FTACS_"..OB_VERSION
MANAGEMENT_KEY = "MGM_"..OB_VERSION

---
--  As chaves CORBALOC para obtenção das interfaces do RS.
---
REGISTRY_SERVICE_KEY = "RS_"..OB_VERSION
REGISTRY_SERVICE_KEY_PREV = "RS_"..OB_PREV
FAULT_TOLERANT_RS_KEY = "FTRS_"..OB_VERSION
FT_RS_MONITOR_KEY = "FTRSMonitor_"..OB_VERSION
MANAGEMENT_RS_KEY = "MGMRS_" .. OB_VERSION

---
--  A interface ISessionService.
---
SESSION_SERVICE_INTERFACE = "IDL:tecgraf/openbus/session_service/"..OB_VERSION..
    "/ISessionService:1.0"

---
--  A interface ISessionService utilizada na versão anterior.
---
SESSION_SERVICE_INTERFACE_PREV = "IDL:tecgraf/openbus/session_service/"..
    OB_PREV.."/ISessionService:1.0"

---
--  A interface SessionEventSink.
---
SESSION_ES_INTERFACE = "IDL:tecgraf/openbus/session_service/"..OB_VERSION..
    "/SessionEventSink:1.0"

---
--  A interface SessioneventSink utilizada na versão anterior.
---
SESSION_ES_INTERFACE_PREV = "IDL:tecgraf/openbus/session_service/"..OB_PREV..
    "/SessionEventSink:1.0"

---
--  A interface ISession.
---
SESSION_INTERFACE = "IDL:tecgraf/openbus/session_service/"..OB_VERSION..
  "/ISession:1.0"

---
--  A interface ISession utilizada na versão anterior.
---
SESSION_INTERFACE_PREV = "IDL:tecgraf/openbus/session_service/"..OB_PREV..
  "/ISession:1.0"

---
--  A interface ICredentialObserver.
---
CREDENTIAL_OBSERVER_INTERFACE = "IDL:tecgraf/openbus/core/"..OB_VERSION..
    "/access_control_service/ICredentialObserver:1.0"

---
--  A interface ICredentialObserver utilizada na versão anterior.
---
CREDENTIAL_OBSERVER_INTERFACE_PREV = "IDL:tecgraf/openbus/core/"..OB_PREV..
    "/access_control_service/ICredentialObserver:1.0"

---
--  A interface IManagement do Servico de Controle de Acesso.
---
MANAGEMENT_ACS_INTERFACE =  "IDL:tecgraf/openbus/core/" .. OB_VERSION ..
  "/access_control_service/IManagement:1.0"


---
--  A interface IManagement do Servico de Registro.
---
MANAGEMENT_RS_INTERFACE =  "IDL:tecgraf/openbus/core/" .. OB_VERSION ..
  "/registry_service/IManagement:1.0"

---
--  O nome da faceta do Serviço de Sessão.
---
SESSION_SERVICE_FACET_NAME = "ISessionService_" .. OB_VERSION

---
--  A interface IHDataService.
---
DATA_SERVICE_INTERFACE = "IDL:openbusidl/data_service/IHDataService:1.0"

---
--  Nome da propriedade que indica o identificador de um componente.
---
COMPONENT_ID_PROPERTY_NAME = "component_id"

---
-- Define as políticas para a validação de credenciais interceptadas em um servidor.
---
CredentialValidationPolicy = {
  -- Indica que as credenciais interceptadas serão sempre validadas.
  "ALWAYS",
  -- Indica que as credenciais interceptadas serão validadas e armazenadas em uma cache.
  "CACHED",
  -- Indica que as credenciais interceptadas não serão validadas.
  "NONE"}

---
-- Obtém referências para as principais facetas do Serviço de Controle de
-- Acesso.
--
-- @param orb O ORB a ser utilizado para obter as facetas.
-- @param host String com o host do Serviço de Controle de Acesso
-- @param port Número ou string com a porta do Serviço de Controle de Acesso
--
-- @return A faceta IAccessControlService, ou nil, caso não seja encontrada.
-- @return A faceta ILeaseProvider, ou nil, caso não seja encontrada.
-- @return A faceta IComponent, ou nil, caso não seja encontrada.
--
function fetchAccessControlService(orb, host, port)
  port = tostring(port)
  local acs = orb:newproxy("corbaloc::".. host .. ":" .. port .. "/" ..
    ACCESS_CONTROL_SERVICE_KEY, "synchronous", ACCESS_CONTROL_SERVICE_INTERFACE)
  if not OilUtilities:existent(acs) then
    Log:error(format("A faceta IAccessControlService_%s não foi encontrada", OB_VERSION))
    error()
  end
  local lp = orb:newproxy("corbaloc::".. host .. ":" .. port .. "/" ..
    LEASE_PROVIDER_KEY, "synchronous", LEASE_PROVIDER_INTERFACE)
  if not OilUtilities:existent(lp) then
    Log:error("Utils: Faceta ILeaseProvider não encontrada.")
    error()
  end
  local ic = orb:newproxy("corbaloc::".. host .. ":" .. port .. "/" ..
      OPENBUS_KEY, "synchronous", "IDL:scs/core/IComponent:1.0")
  if not OilUtilities:existent(ic) then
    Log:error("Utils: Faceta IComponent não encontrada.")
    error()
  end
  local ft = orb:newproxy("corbaloc::".. host .. ":" .. port .. "/" ..  FAULT_TOLERANT_ACS_KEY,
    "synchronous", FAULT_TOLERANT_SERVICE_INTERFACE)
  if not OilUtilities:existent(ft) then
    Log:error("Utils: Faceta IFaultTolerantService não encontrada.")
    error()
  end
  return acs, lp, ic, ft
end

---
-- Obtém uma réplica ativa da lista de réplicas que são receptáculos
-- de dado um componente.  As réplicas são IComponent porém deseja-se
-- obter uma outra faceta deste componente (ex. IRegistryService)
-- ** O ideal seria que esse método estivesse dentro de AdaptiveReceptacle,
-- ou ainda em um receptacleutils dentro do SCS.
-- Porém, como teria que estender a interface IReceptacle ou modificar o SCS,
--  e isso entrará na evolução do SCS até mesmo com a própria
--  AdaptiveReceptacle, optou-se por colocar esse método aqui na Utils.
--
-- @param orb O ORB a ser utilizado para obter a replica.
-- @param component O componente que contém as réplicas como receptáculos
-- @param receptacleName O nome do receptáculo
-- @param replicaIface A interface da faceta da réplica
-- @param replicaIDL A IDL da interface da faceta da réplica
--
-- @return A faceta replicaIface, ou nil, caso não seja encontrada.
--
function getReplicaFacetByReceptacle(orb, component, receptacleName,
                                     replicaIface, replicaIDL)
  local replicaIRecep =  component:getFacetByName("IReceptacles")
  replicaIRecep = orb:narrow(replicaIRecep, "IDL:scs/core/IReceptacles:1.0")
  if replicaIRecep then
    local status, conns = oil.pcall(replicaIRecep.getConnections,
                                    replicaIRecep,
                                    receptacleName)
    if not status then
      Log:error("Nao foi possivel obter o Serviço [".. replicaIface .. "]: " .. conns[1])
      return nil
    elseif conns[1] then
      local recepIC = conns[1].objref
      recepIC = orb:narrow(recepIC, "IDL:scs/core/IComponent:1.0")
      local ok, recepFacet =  oil.pcall(recepIC.getFacetByName, recepIC, replicaIface)
      if ok then
          recepFacet = orb:narrow(recepFacet, replicaIDL)
          if recepFacet then
            return recepFacet
          end
      end
      Log:error("Nao foi possivel obter a faceta [".. replicaIface .. "]: " .. recepFacet)
    end
  end
  Log:error("Nao foi possivel obter o Serviço [".. replicaIface .. "].")
  return nil
end


function fetchService(orb, objReference, objType)
   Log:debug(format("Tentativa de obter o serviço %s do tipo %s", objReference,
       objType))
   local success, service = oil.pcall(orb.newproxy, orb, objReference,
       "synchronous", objType)

   if success then
     if OilUtilities:existent(service) then
       Log:debug(format("O serviço %s foi encontrado", objReference))
       --TODO: Essa linha é devido a um bug no OiL: type_id = ""
       service.__reference.type_id = objType
       -- fim do TODO
       return true, service
      else
        Log:error(format("O serviço %s não foi encontrado", objReference))
        return false, "Servico nao encontrado"
      end
   else
      return false, "Erro: " .. tostring(service)
   end

end

function setInterceptableIfaceMap(ifaceMap, iface, method, interceptable)
  -- Guarda apenas os métodos que não devem ser interceptados
  local methods
  if interceptable then
    methods = ifaceMap[iface]
    if methods then
      methods[method] = nil
      if not next(method) then
        ifaceMap[iface] = nil
      end
    end
  else
    methods = ifaceMap[iface]
    if not methods then
      methods = {}
      ifaceMap[iface] = methods
    end
    methods[method] = true
  end
  return ifaceMap
end

function isInterceptable(ifaceMap, iface, method)
  local methods = ifaceMap[iface]
  return not (methods and methods[method])
end


---
-- Verifica se duas entradas de ofertas com propriedades
-- formadas pelo RSFacet:createPropertyIndex são equivalentes.
--
-- @param offerEntryA Oferta a ser comparada
-- @param offerEntryB Oferta a ser comparada
-- @param orb O ORB a ser utilizado
--
-- @return true se as ofertas pertencem ao mesmo membro com as mesmas propriedades.
--  false em caso contrário.
--
function equalsOfferEntries(offerEntryA, offerEntryB, orb)
  -- (A contido em B) ^ (B contido A) -> (A == B)
  return offerEntryA.credential.identifier == offerEntryB.credential.identifier and
    containsProperties(offerEntryA.properties, offerEntryB.properties)          and
    containsProperties(offerEntryB.properties, offerEntryA.properties)          and
    orb:tostring(offerEntryA.offer.member) == orb:tostring(offerEntryB.offer.member)
end

---
-- Verifica se o primeiro conjunto de propriedades contém o segundo.
--
-- Essas propriedades podem conter o resultado da função RSFacet:createPropertyIndex().
-- Por isso, ignora as propriedades 'component_id', 'registered_by' e 'modified' que são geradas
-- automaticamente, comparando somente os dados fornecidos pelo membro.
--
-- @param propertiesA Propriedades de registro
-- @param propertiesB Propriedades de registro
--
-- @return true se propertiesA contém propertiesB. false, caso contrário.
--
function containsProperties(propertiesA, propertiesB)
  for name, values in pairs(propertiesB) do
    -- Propriedades registradas automaticamente pelo Serviço de Registro: ignorar
    if name ~= "component_id" and
      name ~= "registered_by" and
      name ~= "modified" then
      if type ( values ) == "table" then
        local count = 0
        for value in pairs(values) do
          count = count + 1
          if not (propertiesA[name] and propertiesA[name][value]) then
            return false
          end
        end
        if count == 0 then
        --tabela vazia
          if not propertiesA[name] then
          --propriedade nem existe em A
            return false
          else
            local countA = 0
            for valueA in pairs(propertiesA[name]) do
              countA = countA + 1
            end
            if countA > 0 then
            --existe e tabela nao vazia, logo, nao esta contido
              return false
            end
          end
        end
      end
    end
  end
  return true
end

-- Parser de uma string serializada de descricoes de facetas
-- onde o divisor de cada descricao eh o caracter '#'
-- @return Retorna uma tabela da seguinte forma:
--    facets[facet.name] = true
--    facets[facet.interface_name] = true
--    facets[facet.facet_ref] = true
function unmarshalHashFacets(strFacets)
  local facets = {}
  for facetDesc in string.gmatch(strFacets, "[^#]+") do
    if facetDest then
       facets[facetDesc] = true
    end
  end
  return facets
end

function marshalHashFacets(facets)
  local strFacets = ""
  for facetDesc, value in pairs(facets) do
     if type (facetDesc) ~= "table" then
       -- ignora a reference para a faceta que é uma tabela  ( facet_ref )
       -- que depois é recuperada pela IMetaInterface
       strFacets = tostring(facetDesc) .. "#" .. strFacets
     end
  end
  return strFacets
end

function convertToSendIndexedProperties(indexedProperties)

  local syncProperties = {}

  --transforma propriedades do tipo:
  -- { name = "Hello_v1",
  --   ["Hello_v1:1.0.0"] = true, }
  for k, prop in pairs(syncProperties) do
    if type(prop) == "table" then
      for f, v in pairs(prop) do
        if f == "name" and v ~= "value" and not prop.value then
          prop.value = { tostring(v) }
        end
      end
    end
  end

  --transforma properties["component_id"].name = componentId.name
  table.insert( syncProperties,
               { name="component_id_name",
                 value= { indexedProperties.component_id.name }  } )

  --transforma properties["component_id"][compId] = true
  for field, val in pairs(indexedProperties.component_id) do
     if field ~= "name" then
        table.insert( syncProperties,
               { name="component_id_compId_name" ,
                 value= { field }  } )
        table.insert( syncProperties,
               { name="component_id_compId_val" ,
                 value= { tostring(val) }  } )
     end
  end

  --transforma properties["registered_by"][credential.owner] = true
  for field, val in pairs(indexedProperties.registered_by) do
    table.insert( syncProperties,
              { name="registered_by_credential.owner_name" ,
                value= { field }  } )
    table.insert( syncProperties,
              { name="registered_by_credential.owner_val" ,
                value= { tostring(val) }  } )
  end

  --transforma properties["modified"]['time_in_string'] = true
  for field, val in pairs(indexedProperties.modified) do
    table.insert( syncProperties,
              { name="modified" ,
                value= { field }  } )
  end

  return syncProperties
end

function convertToReceiveIndexedProperties(syncProperties)

  local indexedProperties = {}
  indexedProperties["component_id"] = {}
  indexedProperties["registered_by"] = {}
  indexedProperties["modified"] = {}
  local compId
  local compIdVal

  local credentialOwnerName
  local credentialOwnerVal
  for k, prop in pairs(syncProperties) do
    if type(prop) == "table" then
        if prop.name == "component_id_name" then
          indexedProperties["component_id"].name = prop.value[1]
        elseif prop.name == "component_id_compId_name" then
          compId = prop.value[1]
        elseif prop.name == "component_id_compId_val" then
          compIdVal = prop.value[1]
        elseif prop.name == "registered_by_credential.owner_name" then
          credentialOwnerName = prop.value[1]
        elseif prop.name == "registered_by_credential.owner_val" then
          credentialOwnerVal = prop.value[1]
        elseif prop.name == "modified" then
          indexedProperties["modified"][prop.value[1]] = true
        elseif prop.name then
          indexedProperties[name] = prop.value
        end
    end
  end
  indexedProperties["component_id"][compId] = compIdVal
  indexedProperties["registered_by"][credentialOwnerName] = credentialOwnerVal
  return indexedProperties
end

patt="%-?%-?(%w+)(=?)(.*)"
-- Parsing arguments and returns a 'table[option]=value'
function parse_args(arg, usage_msg, allowempty)
  assert(type(arg)=="table","ERROR: Missing arguments! This program should be loaded from console.")
  local arguments = {}
  -- concatenates with the custom usage_msg
  usage_msg=[[
 Usage: ]]..arg[0]..[[ OPTIONS
 Valid OPTIONS:
]] ..usage_msg

  if not (arg[1]) and not allowempty then print(usage_msg) ; os.exit(1) end

  for i,param in ipairs(arg) do
    local opt,_,value = param:match(patt)
    if opt == "h" or opt == "help" then
      print(usage_msg)
      os.exit(1)
    end
    if opt and value then
      if arguments[opt] then
        arguments[opt] = arguments[opt].." "..value
      else
        arguments[opt] = value
      end
    end
  end

  return arguments
end

function setVerboseOutputFile(verbose, outputFileName)
  local outputFile, errMsg = io.open(outputFileName, "a+")
  if not outputFile then
    return nil, errMsg
  end

  if not verbose.viewer then
    verbose.viewer = Viewer()
  end
  verbose.viewer.output = outputFile
  return outputFile
end

