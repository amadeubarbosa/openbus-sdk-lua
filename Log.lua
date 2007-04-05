--
-- Mecanismo para debug do OpenBus baseado no módulo Verbose provido pelo LOOP
--
-- $Id$
--
local Viewer = require "loop.debug.Viewer"
local Verbose = require "loop.debug.Verbose"

module ("openbus.common.Log", Verbose)

-- Usa uma instância própria do Viewer para não interferir com o do OiL
viewer = Viewer{
           maxdepth = 2,
           indentation = "|  ",
           -- output = io.output()
         }

-- Definição dos tags que compõem cada grupo
groups.basic = {"init", "warn", "error"}
groups.mechanism = {"interceptor"}
groups.core = {"scs", "member"}
groups.all = {"basic", "service", "mechanism", "core"}

-- Definição dos níveis de debug (em ordem crescente)
_M:newlevel{"basic"}
_M:newlevel{"service"}
_M:newlevel{"mechanism"}
_M:newlevel{"core"}

-- Caso seja necessário exibir o horário do registro
-- timed.basic =  "%d/%m %H:%M:%S"
-- timed.all =  "%d/%m %H:%M:%S"
