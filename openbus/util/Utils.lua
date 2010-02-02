-- $Id: $

local type = type
local ipairs = ipairs
local print = print
local tostring = tostring
local assert = assert
local os = os
local string = string
local table  = table
local unpack = unpack
local string = string

local oil = require "oil"
local oop = require "loop.base"
local log = require "openbus.util.Log"
local OilUtilities = require "openbus.util.OilUtilities"


---
-- API utilitária.
---
module "openbus.util.Utils"

---
--  A interface IAccessControlService.
---
ACCESS_CONTROL_SERVICE_INTERFACE =
  "IDL:tecgraf/openbus/core/v1_05/access_control_service/IAccessControlService:1.0"

---
--  A interface ILeaseProvider.
---
LEASE_PROVIDER_INTERFACE = "IDL:tecgraf/openbus/core/v1_05/access_control_service/ILeaseProvider:1.0"

---
--  A interface IFaultTolerantService.
---
FAULT_TOLERANT_SERVICE_INTERFACE = 
  "IDL:tecgraf/openbus/fault_tolerance/v1_05/IFaultTolerantService:1.0"
  
---
--  A interface IComponent.
---
COMPONENT_INTERFACE = 
  "IDL:scs/core/IComponent:1.0"
  
---
--  A interface IRegistryService.
---
REGISTRY_SERVICE_INTERFACE =
  "IDL:tecgraf/openbus/core/v1_05/registry_service/IRegistryService:1.0"

---
--  As chaves CORBALOC para obtenção das interfaces do ACS.
---
ICOMPONENT_KEY = "/IC"
ACCESS_CONTROL_SERVICE_KEY = "/ACS"
LEASE_PROVIDER_KEY = "/LP"
FAULT_TOLERANT_ACS_KEY = "/FTACS"
REGISTRY_SERVICE_KEY = "/RS"
FAULT_TOLERANT_RS_KEY = "/FTRS"

---
--  A interface ISessionService.
---
SESSION_SERVICE_INTERFACE = "IDL:tecgraf/openbus/session_service/v1_05/ISessionService:1.0"

---
--  O nome da faceta do Serviço de Sessão.
---
SESSION_SERVICE_FACET_NAME = "sessionService"

---
--  A interface IHDataService.
---
DATA_SERVICE_INTERFACE = "IDL:openbusidl/data_service/IHDataService:1.0"

---
--  Nome da propriedade que indica o identificador de um componente.
---
COMPONENT_ID_PROPERTY_NAME = "component_id"

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
  local acs = orb:newproxy("corbaloc::".. host .. ":" .. port ..
    ACCESS_CONTROL_SERVICE_KEY, "IDL:tecgraf/openbus/core/v1_05/access_control_service/IAccessControlService:1.0")
  if acs:_non_existent() then
    log:error("Utils: Faceta IAccessControlService não encontrada.")
  end
  local lp = orb:newproxy("corbaloc::".. host .. ":" .. port ..
    LEASE_PROVIDER_KEY, "IDL:tecgraf/openbus/core/v1_05/access_control_service/ILeaseProvider:1.0")
  if lp:_non_existent() then
    log:error("Utils: Faceta ILeaseProvider não encontrada.")
  end
  local ic = orb:newproxy("corbaloc::".. host .. ":" .. port .. ICOMPONENT_KEY,
    "IDL:scs/core/IComponent:1.0")
  if ic:_non_existent() then
    log:error("Utils: Faceta IComponent não encontrada.")
  end
  local ft = orb:newproxy("corbaloc::".. host .. ":" .. port .. FAULT_TOLERANT_ACS_KEY,
    "IDL:tecgraf/openbus/fault_tolerance/v1_05/IFaultTolerantService:1.0")
  if ft:_non_existent() then
    log:error("Utils: Faceta IFaultTolerantService não encontrada.")
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
-- @return A faceta IAccessControlService, ou nil, caso não seja encontrada.
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
	    log:error("Nao foi possivel obter o Serviço [".. replicaIface .. "]: " .. conns[1])
	    return nil
  	elseif conns[1] then 
	    local recepIC = conns[1].objref
	    recepIC = orb:narrow(recepIC, "IDL:scs/core/IComponent:1.0")
        local ok, recepFacet =  oil.pcall(recepIC.getFacetByName, recepIC, replicaIface)
        if ok then
            recepFacet = orb:narrow(recepFacet, replicaIDL)
    	    return recepFacet
    	end
    	log:error("Nao foi possivel obter a faceta [".. replicaIface .. "]: " .. recepFacet)
  	end
  end
  log:error("Nao foi possivel obter o Serviço [".. replicaIface .. "].")
  return nil
end


function fetchService(orb, objReference, objType)
   
   log:faulttolerance("[fetchService]"..objReference.."-TYPE:"..objType)
   local success, service = oil.pcall(orb.newproxy, orb, objReference, objType)

   if success then 
		 --TODO: Quando o bug do oil for consertado, mudar para: if not service:_non_existent() then
		 --local succ, non_existent = service.__try:_non_existent()
		 --if succ and not non_existent then
		if OilUtilities:existent(service) then
	 	     --OK
	         log:faulttolerance("[fetchService] Servico encontrado.")
		     --TODO: Essa linha é devido a um outro bug no OiL: type_id = ""
		     service.__reference.type_id = objType
		     -- fim do TODO
		     
		     return true, service
		 end
    end
    
    log:error("[fetchService]: Servico ".. objReference .." nao encontrado.")
    return false, nil

end

--Verifica se duas entradas de ofertas sao equivalentes
function equalsOfferEntries(offerEntryA, offerEntryB)
	if  offerEntryA.credential == offerEntryB.credential and
		offerEntryA.offer.properties == offerEntryB.offer.properties and
		offerEntryA.allFacets == offerEntryB.offer.allFacets then
		return true
	elseif offerEntryA.credential == offerEntryB.credential and
		   offerEntryA.offer.properties == offerEntryB.offer.properties and
		   offerEntryA.allFacets ~= offerEntryB.offer.allFacets then
		 Log:faultolerance("[warn][equalsOfferEntries] Servico possui uma oferta similar "..
		 					"em replicas diferentes e sua lista de facetas diferem.")
		 return false
	else
		return false
	end
end


-- Parser de uma string serializada de descricoes de facetas
-- onde o divisor de cada descricao eh o caracter '#'
-- @return Retorna uma tabela da seguinte forma:
--	  facets[facet.name] = true
--    facets[facet.interface_name] = true
--    facets[facet.facet_ref] = true
function unmarshalHashFacets(strFacets)
	local facets = {}
	for facetDesc in string.gmatch(strFacets, "[^#]+") do
		facets[facetDesc] = true
	end
	return facets
end

function marshalHashFacets(facets)
    local strFacets = ""
    for facetDesc, value in ipairs(facets) do
   	    strFacets = strFacets .. "#" .. facetDesc
   	end
   	return strFacets
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




