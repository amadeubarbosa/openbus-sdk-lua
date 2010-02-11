-- $Id$

local print  = print
local pairs  = pairs
local ipairs = ipairs
local format = string.format
local coroutine = coroutine

local oil = require "oil"
local orb = oil.orb

local Openbus   = require "openbus.Openbus"
local Log       = require "openbus.util.Log"
local PICurrent = require "openbus.interceptors.PICurrent"
local ServiceStatusManager = require "openbus.faulttolerance.ServiceStatusManager"

local oop  = require "loop.base"
local giop = require "oil.corba.giop"

---
--Interceptador de requisi��es de servi�o, respons�vel por verificar se o
--emissor da requisi��o foi autenticado (possui uma credencial v�lida).
---
module("openbus.interceptors.ServerInterceptor", oop.class)

---
--Constr�i o interceptador.
--
--@param config As configura��es do interceptador.
--@param accessControlService O servi�o de controle de acesso.
--
--@return O interceptador.
---
function __init(self, config, accessControlService)
  Log:interceptor("Construindo interceptador para servi�o")
  local lir = Openbus:getORB():getLIR()
  
  -- Obt�m as opera��es das interfaces que devem ser verificadas
  if config.interfaces then
    for _, iconfig in ipairs(config.interfaces) do
      Log:interceptor(true, format("Checar interface: %s", iconfig.interface))
      for _, op in ipairs(iconfig.excluded_ops or {}) do
        Openbus:setInterceptable(iconfig.interface, op, false)
        Log:interceptor(format("N�o checar opera��o: %s", op))
      end
      Log:interceptor(false)
    end
  else
    -- Se nenhuma interface especificada, checa todas as opera��es
    Log:interceptor("checar todas as opera��es de qualquer interface")
  end

  -- Adiciona as opera��es de CORBA como n�o verificadas.
  -- A classe Object de CORBA n�o tem repID, criar um identificar interno.
  for op in pairs(giop.ObjectOperations) do
    Openbus:setInterceptable("::CORBA::Object", op, false)
  end
  return oop.rawnew(self, {
    credentialType = lir:lookup_id(config.credential_type).type,
    contextID = config.contextID,
    picurrent = PICurrent(),
    accessControlService = accessControlService,
    serviceStatusManager = ServiceStatusManager:__init()
  })
end

---
--Intercepta o request para obten��o da informa��o de contexto (credencial).
--
--@param request Dados sobre o request.
---
function receiverequest(self, request)
  Log:interceptor "INTERCEPTA��O SERVIDOR!"
  
  -- XXX: nao existe forma padrao de recuperar o repID, esta e' uma
  -- intrusao no OiL, ou seja, pode quebrar no futuro.
  local repID = orb.ServantIndexer.indexer:typeof(request.object_key).repID
  local allowed = not (Openbus:isInterceptable(repID, request.operation) and
    Openbus:isInterceptable("::CORBA::Object", request.operation))

  if (repID == "IDL:tecgraf/openbus/core/v1_05/access_control_service/IAccessControlService:1.0") and
     (request.operation == "loginByPassword")
  then
    Log:interceptor("Desligando verbose do dispatcher...")
    oil.verbose:flag("dispatcher", false)
  end

  if allowed then
    Log:interceptor(format("OPERA��O %s N�O � CHECADA", request.operation))
    return
  else
  	Log:interceptor(format("OPERA��O %s � CHECADA", request.operation))

  	local credential
  	for _, context in ipairs(request.service_context) do
    	if context.context_id == self.contextID then
	      Log:interceptor "TEM CREDENCIAL!"
    	  local decoder = orb:newdecoder(context.context_data)
	      credential = decoder:get(self.credentialType)
    	  Log:interceptor(format("CREDENCIAL: %s, %s", credential.identifier,
        	 credential.owner))
      	  break
    	end
  	end

  	if credential then
    	local success, res = oil.pcall(self.accessControlService.isValid,
        	                           self.accessControlService, credential)
    	if success and res then
    	  	Log:interceptor(format("CREDENCIAL VALIDADA PARA %s", request.operation))
      		self.picurrent:setValue(credential)
      		return
    	end
  	end
  	
	-- Credencial inv�lida ou sem credencial
	if credential then
   		Log:interceptor("\n ***CREDENCIAL INVALIDA ***\n")
	else
  		Log:interceptor("\n***N�O TEM CREDENCIAL ***\n")
	end
	request.success = false
	request.count = 1
	request[1] = orb:newexcept{"CORBA::NO_PERMISSION", minor_code_value = 0}
  	
  end
  
end

---
--Intercepta a resposta ao request para "limpar" o contexto.
--
--@param request Dados sobre o request.
---
function sendreply(self, request)
  if (request.operation == "loginByPassword") then
    Log:interceptor("Ligando verbose do dispatcher...")
    oil.verbose:flag("dispatcher", true)
  end
  request.service_context = {}
  
  if self:needUpdate(request) then
    local key = request.object_key
    --VER COM O MAIA (10/02/2010) : Por algum motivo o request.object_key nao esta vindo
	-- com o key do servico de registro, so funciona para o ACS
	if request.operation == "register" or
  	   request.operation == "update"  then  	   
  		key = "RS"
  	end
    oil.newthread(function() 
  				 self.serviceStatusManager:updateStatus(key) 
  				  end)
  end
end

---
--Obt�m a credencial da entidade que est� realizando uma requisi��o.
--
--@return A credencial da entidade.
---
function getCredential(self)
  return self.picurrent:getValue()
end

function needUpdate(self, request)
	--TODO: Colocar aqui somente o que faz sentido pedir para atualizar
	-- o estado antes
	-- ***pensar como ficara o unregister do RGS
	if request.operation == "loginByPassword" 	 or
  	   request.operation == "loginByCertificate" or
  	   request.operation == "renewLease" or
  	   request.operation == "register" or
  	   request.operation == "addObserver" or
  	   request.operation == "removeObserver" or
  	   request.operation == "addCredentialToObserver" or
  	   request.operation == "removeCredentialFromObserver" or
  	   request.operation == "update" then  	   
  		return true
  		
  	end
  	return false
end
