local msg = require "openbus.util.messages"

-- openbus.core.Access
msg.UnableToDecodeCredential = "falha na leitura de credencial: $errmsg"
msg.MissingCallerInfo = "recebida chamada de $operation sem credencial"
msg.InvokeWithoutCredential = "chamando opera��o $operation sem credencial"
msg.InvokeWithCredential = "chamando opera��o $operation com credencial de $entity (login=$login)"
msg.GrantedCallWithoutCallerInfo = "autorizada chamada de $operation sem credencial"
msg.GrantedCall = "autorizada chamada de $operation por $entity (login=$login)"
msg.DeniedCall = "negada chamada de $operation por $entity (login=$login)"
msg.GotInvalidCaller = "chamando opera��o $operation com credencial inv�lida de $entity (login=$login)"

-- openbus.core.util.server
msg.ConfigFileNotFound = "o arquivo de configura��o $path n�o foi encontrado"
msg.BadParamInConfigFile = "o par�metro $configname definido no arquivo $path � inv�lido"
msg.BadParamTypeInConfigFile = "o par�metro $configname foi definido no arquivo $path com um valor do tipo $actual, mas deveria ser do tipo $expected"
msg.BadParamListInConfigFile = "o par�metro $configname definido no arquivo $path tem um valor inv�lido na posi��o $index"
msg.BadLogFile = "n�o foi poss�vel abrir o arquivo de log $path: errmsg"
--msg.UnableToReadFileContents = "$path $errmsg"
--msg.UnableToReadPublicKey = "$path $errmsg"
--msg.UnableToReadPrivateKey = "$path $errmsg"

return msg
