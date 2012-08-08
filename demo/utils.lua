local _G = require "_G"
local tostring = _G.tostring
local type = _G.type

local io = require "io"
local stderr = io.stderr

local proto = require "loop.proto"
local clone = proto.clone

local openbus = require "openbus"
local sleep = openbus.sleep

local except = require "openbus.util.except"
local repid = except.repid
local minor = except.minor

require "openbus.util.messages"

local BusExceptions = {
  [repid.ServiceFailure]
    = "falha severa no barramento em $bushost:$busport ($message)",
  [repid.TRANSIENT]
    = "o barramento em $bushost:$busport está inacessível no momento",
  [repid.COMM_FAILURE]
    = "falha de comunicação ao acessar serviços núcleo do barramento",
}
local ConnectExceptions = clone(BusExceptions, {
  [repid.InvalidBusAddress]
    = "o endereço $bushost:$busport não indica um barramento válido",
})
local LoginByPasswordExceptions = clone(BusExceptions, {
  [repid.InvalidBusAddress]
    = "o endereço $bushost:$busport não indica um barramento válido",
  [repid.AccessDenied]
    = "a senha fornecida para a entidade $entity foi negada",
})
local LoginByCertificateExceptions = clone(BusExceptions, {
  [repid.InvalidBusAddress]
    = "o endereço $bushost:$busport não indica um barramento válido",
  [repid.AccessDenied]
    = "a chave em $privatekeypath não corresponde ao certificado da "..
      "entidade $entity",
  [repid.InvalidPrivateKey]
    = "a chave em $privatekeypath não é válida ($message)",
  [repid.MissingCertificate]
    = "a entidade $entity não possui um certificado registrado",
})
local RegisterExceptions = clone(BusExceptions, {
  [repid.UnauthorizedFacets]
    = "a entidade $entity não foi autorizada pelo administrador do "..
      "barramento a ofertar serviços que implementem a interface $interface",
})
local ServiceExceptions = {
  [repid.TRANSIENT]
    = "o serviço encontrado está inacessível",
  [repid.COMM_FAILURE]
    = "falha de comunicação com o serviço encontrado",
  [repid.NO_PERMISSION] = {
    [minor.NoLogin]
      = "o login de $entity se tornou inválido durante a execução",
    [minor.UnknownBus]
      = "o serviço encontrado não está mais logado ao barramento",
    [minor.UnverifiedLogin]
      = "o serviço encontrado não foi capaz de validar a chamada",
    [minor.InvalidRemote]
      = "integração do serviço encontrado com o barramento está incorreta",
  }
}


local module = {
  msg = {
    Bus = BusExceptions,
    Connect = ConnectExceptions,
    LoginByCertificate = LoginByCertificateExceptions,
    LoginByPassword = LoginByPasswordExceptions,
    Register = RegisterExceptions,
    Service = ServiceExceptions,
  },
}

function module.showerror(errmsg, params, ...)
  local repid = errmsg._repid
  for index = 1, select("#", ...) do
    local expected = select(index, ...)
    local message = expected[repid]
    if message ~= nil then
      if type(message) == "table" then
        message = message[errmsg.minor]
      end
      if message ~= nil then
        errmsg = message:tag(clone(errmsg, params))
        setmetatable(params, nil)
      end
      break
    end
  end
  stderr:write(tostring(errmsg), "\n")
end

function module.getprop(offer, name)
  for _, property in ipairs(offer.properties) do
    if property.name == name then
      return property.value
    end
  end
end

return module
