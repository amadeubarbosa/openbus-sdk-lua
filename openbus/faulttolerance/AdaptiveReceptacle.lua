
local scs = require "scs.core.base"
local Log = require "openbus.util.Log"
local oop = require "loop.simple"
local print = print
local pairs = pairs
local tostring = tostring

local oil = require "oil"
local orb = oil.orb

local OilUtilities = require "openbus.util.OilUtilities"

module("openbus.faulttolerance.AdaptiveReceptacle")
--
-- Receptacles Class
-- Implementation of the IReceptacles Interface from scs.idl
--
 

AdaptiveReceptacleFacet = oop.class({}, scs.Receptacles)

--The first of the list always starts as the leader
local activeConnId = 1

function AdaptiveReceptacleFacet:updateActiveConnId(conns)
	Log:faulttolerance("[AdaptiveReceptacleFacet:updateActiveConnId]")

	if # conns == 0 then
	--if the list is empty, there aren't active receptacle
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

    self:updateConnections(receptacle)
    -- Connects the service at the receptacle
    local connId = scs.Receptacles.connect(self,
  	 								 	    receptacle, 
  										    object) -- calling inherited method
    if not connId then
        Log:faulttolerance("Falha ao conectar o Servico no receptaculo")
        return connId
    elseif connId == 1 then 
    -- this is the first to connect
    -- make sure that the reference to the leader is correct
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
	self:updateConnections(receptacle)
	return scs.Receptacles.getConnections(self,receptacle) -- calling inherited method
end

--
--@see AdaptiveReceptacleFacet#updateConnections
--
-- Description: Disconnects any non existent service of a receptacle.
-- Parameter receptacle: The receptacle's name.
--
function AdaptiveReceptacleFacet:updateConnections(receptacle)
    Log:faulttolerance("[AdaptiveReceptacleFacet:updateConnections]")
    local conns = scs.Receptacles.getConnections(self,receptacle)
    if conns then 
    -- each connected service is tested, 
    -- if a communication failure happened, the service is disconnected
    	local alreadyUpdated = false
        for connId,conn in pairs(conns) do
        Log:faulttolerance("[AdaptiveReceptacleFacet:updateConnections] Testando conexao [".. tostring(connId) .."]")
            local serviceRec = orb:narrow(conn.objref, "IDL:scs/core/IComponent:1.0")
            if not OilUtilities:existent(serviceRec) then
               Log:faulttolerance("[AdaptiveReceptacleFacet:updateConnections] Nao encontrou receptaculo, vai desconectar.")
               -- serviceRec esta com falha -> desconectar
               self:disconnect(connId)
               
               if self.activeConnId == connId and not alreadyUpdated then
                  --atualiza receptacle lider
                  self:updateActiveConnId(conns)
                  alreadyUpdated = true
               end
            end
        end
    end
end
