
local scs = require "scs.core.base"
local Log = require "openbus.util.Log"
local oop = require "loop.simple"
local print = print
local pairs = pairs

module("openbus.faulttolerance.AdaptiveReceptacle")
--
-- Receptacles Class
-- Implementation of the IReceptacles Interface from scs.idl
--
 

AdaptiveReceptacleFacet = oop.class({}, scs.Receptacles)

--sempre começa o primeiro sendo o líder
local activeConnId = 1

function AdaptiveReceptacleFacet:updateActiveConnId(conns)
	
	if # conns == 0 then
	--se nao tem ninguem na lista, nao tem recepatculo ativo
	   self.activeConnId = 0
	else
		if self.activeConnId == # conns then
	   		self.activeConnId = 1
    	else
       		self.activeConnId = self.activeConnId + 1
		end
	end
end

--
--@see scs.core.Receptacles#connect
--
-- Description: Connects an object to the specified receptacle.
-- Parameter receptacle: The receptacle's name that corresponds to the interface implemented by the
--             provided object.
-- Parameter object: The CORBA object that implements the expected interface.
-- Return Value: The connection's identifier.
--
function AdaptiveReceptacleFacet:connect(receptacle, object)

	Log:faulttolerance("[AdaptiveReceptacleFacet:connect]")

    local status, conns = self:getConnections(receptacle)
    if not status then
      Log:error("Erro ao obter as conexões do receptáculo: " .. conns[1])
      return false
    elseif conns then 
    --JA TEM SERVICO CONECTADO, TESTA SE ESTAO
    -- EM ESTADO DE FALHA E PRECISA DESCONECTAR ALGUM CASO AFIRMATIVO
    	local alreadyUpdated = false
        for connId,objref in pairs(conns) do
            local serviceRec = Openbus:getORB():narrow(objref,
                                       "IDL:scs/core/IComponent:1.0")
            if serviceRec:_non_existent() then
            -- serviceRec está com falha -> desconectar
               self:disconnect(connId)
               
               if self.activeConnId == connId and not alreadyUpdated then
                  --atualiza receptacle lider
                  self:updateActiveConnId(conns)
                  alreadyUpdated = true
               end
            end
        end
    end
    -- Conectar Serviço no receptáculo
    local connId = scs.Receptacles.connect(self,
  	 								 	    receptacle, 
  										    object) -- calling inherited method
    if not connId then
        Log:faulttolerance("Falha ao conectar o Serviço no receptáculo")
        return connId
    elseif connId == 1 then 
    -- é o primeiro a conectar
    -- como pode ter acontecido de todos terem se desconectado e
    -- o receptaculo ativo ter ido a 0, melhor garantir que quando tem 1
    -- conectado, a referencia para o ativo sempre é atualizada para 1
    	self.activeConnId = 1
    end
	Log:faulttolerance("[AdaptiveReceptacleFacet:connect] Servico conectado com sucesso")
    return connId
	
end

--
--@see scs.core.Receptacles#disconnect
--
-- Description: Disconnects an object from a receptacle.
-- Parameter connId: The connection's identifier.
--
function AdaptiveReceptacleFacet:disconnect(connId)
	Log:faulttolerance("[AdaptiveReceptacleFacet:disconnect]")
    return scs.Receptacles.disconnect(self,connId) -- calling inherited method
	
end

--
--@see scs.core.Receptacles#getConnections
--
-- Description: Provides information about all the current connections of a receptacle.
-- Parameter receptacle: The receptacle's name.
-- Return Value: All current connections of the specified receptacle.
--
function AdaptiveReceptacleFacet:getConnections(receptacle)
	Log:faulttolerance("[AdaptiveReceptacleFacet:getConnections]")
	return scs.Receptacles.getConnections(self,receptacle) -- calling inherited method
end
