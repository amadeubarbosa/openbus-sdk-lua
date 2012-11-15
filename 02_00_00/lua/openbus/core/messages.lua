local msg = require "openbus.util.messages"

-- openbus.core.Access
msg.UnableToDecodeCredential = "falha na leitura de credencial: $errmsg"
msg.MissingCallerInfo = "recebida chamada de $operation sem credencial"
msg.InvokeWithoutCredential = "chamando operação $operation sem credencial"
msg.InvokeWithCredential = "chamando operação $operation com credencial de $entity (login=$login)"
msg.GrantedCallWithoutCallerInfo = "autorizada chamada de $operation sem credencial"
msg.GrantedCall = "autorizada chamada de $operation por $entity (login=$login)"
msg.DeniedCall = "negada chamada de $operation por $entity (login=$login)"
msg.GotInvalidCaller = "chamando operação $operation com credencial inválida de $entity (login=$login)"

-- openbus.core.util.server
msg.ConfigFileNotFound = "o arquivo de configuração $path não foi encontrado"
msg.BadParamInConfigFile = "o parâmetro $configname definido no arquivo $path é inválido"
msg.BadParamTypeInConfigFile = "o parâmetro $configname foi definido no arquivo $path com um valor do tipo $actual, mas deveria ser do tipo $expected"
msg.BadParamListInConfigFile = "o parâmetro $configname definido no arquivo $path tem um valor inválido na posição $index"
msg.BadLogFile = "não foi possível abrir o arquivo de log $path: errmsg"
--msg.UnableToReadFileContents = "$path $errmsg"
--msg.UnableToReadPublicKey = "$path $errmsg"
--msg.UnableToReadPrivateKey = "$path $errmsg"

return msg
