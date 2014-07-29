
local Viewer = require "loop.debug.Viewer"
local Verbose = require "loop.debug.Verbose"
--local oop = require "loop.simple"
---
--Mecanismo para log de teste de robustez do OpenBus
--baseado no módulo Verbose provido pelo LOOP
---

module "openbus.util.TestLog"

function TestLog()
               return Verbose{
                       timed = "%d/%m; %H:%M:%S",

                       viewer = Viewer{ maxdepth = 2, indentation = "|  " },
                       groups = {
                               {"basic"},
                               basic = {"receiverequest", "sendreply"},
                               all = {"basic"},
                       },
               }
       end

       return TestLog



