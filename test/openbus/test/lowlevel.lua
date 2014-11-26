local struct = require "struct"
local encode = struct.pack

local oil = require "oil"
local newORB = oil.init

local cothread = require "cothread"
local running = cothread.running

local uuid = require "uuid"
local newid = uuid.new
local validid = uuid.isvalid

local hash = require "lce.hash"
local sha256 = hash.sha256
local pubkey = require "lce.pubkey"
local decodepubkey = pubkey.decodepublic

local idl = require "openbus.core.idl"
local loadIDL = idl.loadto
local BusLogin = idl.const.BusLogin
local EncryptedBlockSize = idl.const.EncryptedBlockSize
local CredentialContextId = idl.const.credential.CredentialContextId
local loginconst = idl.const.services.access_control
local logintypes = idl.types.services.access_control
local offertypes = idl.types.services.offer_registry
local credtypes = idl.types.credential

require "openbus.test.configs"

do -- CORBA GIOP message context manipuation functions
  
  local receive = {
    request = {},
    reply = {},
  }
  local send = {
    request = {},
    reply = {},
  }

  local iceptor = {}
  function iceptor:sendrequest(request)
    local thread = running()
    request.service_context = send.request[thread]
    send.request[thread] = nil
    receive.reply[thread] = nil
  end
  function iceptor:receivereply(request)
    local thread = running()
    receive.reply[thread] = request.reply_service_context
  end
  function iceptor:receiverequest(request)
    local thread = running()
    receive.request[thread] = request.service_context
  end
  function iceptor:sendreply(request)
    local thread = running()
    receive.request[thread] = nil
    request.reply_service_context = send.reply[thread]
    send.reply[thread] = nil
  end

  local orb
  function initORB()
    orb = newORB{ flavor = "cooperative;corba.intercepted" }
    orb:setinterceptor(iceptor, "corba")
    return orb
  end
  
  function encodeCDR(value, type)
    local encoder = orb:newencoder()
    encoder:put(value, orb.types:lookup_id(type))
    return encoder:getdata()
  end
  function decodeCDR(stream, type)
    return orb:newdecoder(stream):get(orb.types:lookup_id(type))
  end

  function putreqcxt(tag, data)
    local contexts = send.request[running()]
    if contexts == nil then
      contexts = {}
      send.request[running()] = contexts
    end
    contexts[tag] = data
  end
  function getrepcxt(tag)
    local contexts = receive.reply[running()]
    if contexts ~= nil then
      return contexts[tag]
    end
  end
  function getreqcxt(tag)
    local contexts = receive.request[running()]
    if contexts ~= nil then
      return contexts[tag]
    end
  end
  function putrepcxt(tag, data)
    local contexts = send.reply[running()]
    if contexts == nil then
      contexts = {}
      send.reply[running()] = contexts
    end
    contexts[tag] = data
  end
end

do -- protocol data encoding functions
  function calculateHash(secret, ticket, opname)
    return sha256("\002\001"..encode(
      "<c0I4c0", -- '<' flag to set to little endian
      secret,    -- 'c0' sequence of all chars of a string
      ticket,    -- 'I4' unsigned integer with 4 bytes
      opname))   -- 'c0' sequence of all chars of a string
  end

  function encodeCredential(data)
    data.hash = calculateHash(data.secret, data.ticket, data.opname)
    return encodeCDR(data, credtypes.CredentialData)
  end

  function decodeCredential(stream)
    return decodeCDR(stream, credtypes.CredentialData)
  end

  function encodeReset(data)
    return encodeCDR(data, credtypes.CredentialReset)
  end

  function decodeReset(stream, prvkey)
    local reset = decodeCDR(stream, credtypes.CredentialReset)
    reset.secret = assert(prvkey:decrypt(reset.challenge))
    return reset
  end

  function decodeChain(buskey, signed)
    local encoded = signed.encoded
    assert(buskey:verify(sha256(encoded), signed.signature))
    return decodeCDR(encoded, logintypes.CallChain)
  end

  function encodeLogin(buskey, data, pubkey)
    return buskey:encrypt(encodeCDR({data = data, hash = sha256(pubkey)},
                                    logintypes.LoginAuthenticationInfo))
  end
end

do -- protocol predefined formats
  NullChain = {
    signature = string.rep("\000", EncryptedBlockSize),
    encoded = "",
  }
end

function connectToBus(host, port, orb)
  if orb == nil then orb = initORB(orb) end
  loadIDL(orb)
  
  local bus = orb:newproxy(
    "corbaloc::"..host..":"..port.."/"..idl.const.BusObjectKey,
    nil, -- default proxy type
    "scs::core::IComponent")
  
  local AccessControl = assert(bus:getFacet(logintypes.AccessControl))
  AccessControl = orb:narrow(AccessControl, logintypes.AccessControl)
  local OfferRegistry = assert(bus:getFacet(offertypes.OfferRegistry))
  OfferRegistry = orb:narrow(OfferRegistry, offertypes.OfferRegistry)
  
  return {
    id = assert(AccessControl:_get_busid()),
    key = assert(decodepubkey(AccessControl:_get_buskey())),
    component = bus,
    AccessControl = AccessControl,
    OfferRegistry = OfferRegistry,
    objects = {
      [AccessControl] = true,
      [OfferRegistry] = true,
    }
  }, orb
end

function initBusSession(bus, login)
  putreqcxt(CredentialContextId, encodeCredential{
    opname = "renew",
    bus = bus.id,
    login = login.id,
    session = 0,
    ticket = 0,
    secret = string.rep("\000", 16),
    chain = NullChain,
  })
  local AccessControl = bus.AccessControl
  local ok, ex = pcall(AccessControl.renew, AccessControl)
  assert(ok == false)
  assert(ex._repid == "IDL:omg.org/CORBA/NO_PERMISSION:1.0")
  assert(ex.completed == "COMPLETED_NO")
  assert(ex.minor == loginconst.InvalidCredentialCode)
  local reset = decodeReset(assert(getrepcxt(CredentialContextId)), login.prvkey)
  assert(reset.target == BusLogin)
  reset.ticket = 0
  function reset:newCred(opname, chain)
    local ticket = self.ticket+1
    self.ticket = ticket
    putreqcxt(CredentialContextId, encodeCredential{
      opname = opname,
      bus = bus.id,
      login = login.id,
      session = self.session,
      ticket = ticket,
      secret = self.secret,
      chain = chain or self.chain or NullChain,
    })
  end
  return reset
end

function loginByPassword(bus, user, password, prvkey)
  local pubkey = prvkey:encode("public")
  local encrypted = encodeLogin(bus.key, password, pubkey)
  local login, lease = bus.AccessControl:loginByPassword(user, domain, pubkey, encrypted)
  assert(validid(login.id))
  assert(login.entity == user)
  assert(lease > 0)
  login.prvkey = prvkey
  login.busSession = initBusSession(bus, login)
  return login, lease
end

function testBusCall(bus, login, otherkey, assertresults, proxy, opname, ...)
  local reset, chain

  do -- no credential
    local ok, ex = pcall(proxy[opname], proxy, ...)
    assert(ok == false)
    assert(ex._repid == "IDL:omg.org/CORBA/NO_PERMISSION:1.0")
    assert(ex.completed == "COMPLETED_NO")
    assert(ex.minor == loginconst.NoCredentialCode)
    assert(getrepcxt(CredentialContextId) == nil)
  end

  do -- illegal credential
    putreqcxt(CredentialContextId, "ILLEGAL CDR STREAM")
    local ok, ex = pcall(proxy[opname], proxy, ...)
    assert(ok == false)
    assert(ex._repid == "IDL:omg.org/CORBA/MARSHAL:1.0")
    assert(getrepcxt(CredentialContextId) == nil)
  end

  do -- credential with fake login
    putreqcxt(CredentialContextId, encodeCredential{
      opname = opname,
      bus = bus.id,
      login = "FakeLogin",
      session = 0,
      ticket = 0,
      secret = "",
      chain = NullChain,
    })
    local ok, ex = pcall(proxy[opname], proxy, ...)
    assert(ok == false)
    assert(ex._repid == "IDL:omg.org/CORBA/NO_PERMISSION:1.0")
    assert(ex.completed == "COMPLETED_NO")
    assert(ex.minor == loginconst.InvalidLoginCode)
    assert(getrepcxt(CredentialContextId) == nil)
  end

  do -- credential with fake bus ID
    putreqcxt(CredentialContextId, encodeCredential{
      opname = opname,
      bus = "FakeBus",
      login = login.id,
      session = 0,
      ticket = 0,
      secret = "",
      chain = NullChain,
    })
    local ok, ex = pcall(proxy[opname], proxy, ...)
    assert(ok == false)
    assert(ex._repid == "IDL:omg.org/CORBA/NO_PERMISSION:1.0")
    assert(ex.completed == "COMPLETED_NO")
    assert(ex.minor == loginconst.UnknownBusCode)
    assert(getrepcxt(CredentialContextId) == nil)
  end

  do -- invalid credential
    putreqcxt(CredentialContextId, encodeCredential{
      opname = opname,
      bus = bus.id,
      login = login.id,
      session = 1234,
      ticket = 4321,
      secret = string.rep("\171", 16),
      chain = NullChain,
    })
    local ok, ex = pcall(proxy[opname], proxy, ...)
    assert(ok == false)
    assert(ex._repid == "IDL:omg.org/CORBA/NO_PERMISSION:1.0")
    assert(ex.completed == "COMPLETED_NO")
    assert(ex.minor == loginconst.InvalidCredentialCode)
    reset = decodeReset(assert(getrepcxt(CredentialContextId)), login.prvkey)
    if bus.objects[proxy] then
      assert(reset.target == BusLogin)
      chain = NullChain
    else
      assert(reset.target ~= BusLogin)
      login.busSession:newCred("signChainFor")
      chain = bus.AccessControl:signChainFor(reset.entity)
    end
  end

  do -- valid credential
    putreqcxt(CredentialContextId, encodeCredential{
      opname = opname,
      bus = bus.id,
      login = login.id,
      session = reset.session,
      ticket = 1,
      secret = reset.secret,
      chain = chain,
    })
    assertresults(proxy[opname](proxy, ...))
  end

  do -- credential with wrong busid
    local credential = {
      opname = opname,
      bus = newid(),
      login = login.id,
      session = reset.session,
      ticket = 2,
      secret = reset.secret,
      chain = chain,
    }
    putreqcxt(CredentialContextId, encodeCredential(credential))
    local ok, ex = pcall(proxy[opname], proxy, ...)
    assert(ok == false)
    assert(ex._repid == "IDL:omg.org/CORBA/NO_PERMISSION:1.0")
    assert(ex.completed == "COMPLETED_NO")
    assert(ex.minor == loginconst.UnknownBusCode)
    assert(getrepcxt(CredentialContextId) == nil)
    credential.bus = bus.id -- use the correct bus.id now
    putreqcxt(CredentialContextId, encodeCredential(credential))
    assertresults(proxy[opname](proxy, ...))
  end

  do -- credential with wrong secret
    local credential = {
      opname = opname,
      bus = bus.id,
      login = login.id,
      session = reset.session,
      ticket = 3,
      secret = string.rep("\171", 16),
      chain = chain,
    }
    putreqcxt(CredentialContextId, encodeCredential(credential))
    local ok, ex = pcall(proxy[opname], proxy, ...)
    assert(ok == false)
    assert(ex._repid == "IDL:omg.org/CORBA/NO_PERMISSION:1.0")
    assert(ex.completed == "COMPLETED_NO")
    assert(ex.minor == loginconst.InvalidCredentialCode)
    decodeReset(assert(getrepcxt(CredentialContextId)), login.prvkey)
    credential.secret = reset.secret -- use the correct secret now
    putreqcxt(CredentialContextId, encodeCredential(credential))
    assertresults(proxy[opname](proxy, ...))
  end

  do -- credential with wrong operation name
    local credential = {
      opname = "fake_"..opname,
      bus = bus.id,
      login = login.id,
      session = reset.session,
      ticket = 4,
      secret = reset.secret,
      chain = chain,
    }
    putreqcxt(CredentialContextId, encodeCredential(credential))
    local ok, ex = pcall(proxy[opname], proxy, ...)
    assert(ok == false)
    assert(ex._repid == "IDL:omg.org/CORBA/NO_PERMISSION:1.0")
    assert(ex.completed == "COMPLETED_NO")
    assert(ex.minor == loginconst.InvalidCredentialCode)
    decodeReset(assert(getrepcxt(CredentialContextId)), login.prvkey)
    credential.opname = opname -- use the correct operation name now
    putreqcxt(CredentialContextId, encodeCredential(credential))
    assertresults(proxy[opname](proxy, ...))
  end

  do -- credential with used ticket
    local credential = {
      opname = opname,
      bus = bus.id,
      login = login.id,
      session = reset.session,
      ticket = 4,
      secret = reset.secret,
      chain = chain,
    }
    putreqcxt(CredentialContextId, encodeCredential(credential))
    local ok, ex = pcall(proxy[opname], proxy, ...)
    assert(ok == false)
    assert(ex._repid == "IDL:omg.org/CORBA/NO_PERMISSION:1.0")
    assert(ex.completed == "COMPLETED_NO")
    assert(ex.minor == loginconst.InvalidCredentialCode)
    decodeReset(assert(getrepcxt(CredentialContextId)), login.prvkey)
    credential.ticket = 5 -- use a fresh ticket now
    putreqcxt(CredentialContextId, encodeCredential(credential))
    assertresults(proxy[opname](proxy, ...))
  end

  do -- credential with other login (impersonating someone else)
    local newlogin = loginByPassword(bus, user, password, otherkey)
    local newchain = NullChain
    if not bus.objects[proxy] then
      newlogin.busSession:newCred("signChainFor")
      newchain = bus.AccessControl:signChainFor(reset.entity)
    end

    local credential = {
      opname = opname,
      bus = bus.id,
      login = newlogin.id,
      session = reset.session,
      ticket = 6,
      secret = reset.secret,
      chain = newchain,
    }
    putreqcxt(CredentialContextId, encodeCredential(credential))
    local ok, ex = pcall(proxy[opname], proxy, ...)
    assert(ok == false)
    assert(ex._repid == "IDL:omg.org/CORBA/NO_PERMISSION:1.0")
    assert(ex.completed == "COMPLETED_NO")
    assert(ex.minor == loginconst.InvalidCredentialCode)
    decodeReset(assert(getrepcxt(CredentialContextId)), otherkey)
    credential.login = login.id -- use the correct login now
    credential.chain = chain -- use the correct chain now
    putreqcxt(CredentialContextId, encodeCredential(credential))
    assertresults(proxy[opname](proxy, ...))

    -- logout the new login from the bus
    newlogin.busSession:newCred("logout")
    bus.AccessControl:logout()
  end

  do -- credential with login not valid anymore
    putreqcxt(CredentialContextId, encodeCredential{
      opname = opname,
      bus = bus.id,
      login = newid(),
      session = reset.session,
      ticket = 7,
      secret = reset.secret,
      chain = chain,
    })
    local ok, ex = pcall(proxy[opname], proxy, ...)
    assert(ok == false)
    assert(ex._repid == "IDL:omg.org/CORBA/NO_PERMISSION:1.0")
    assert(ex.completed == "COMPLETED_NO")
    assert(ex.minor == loginconst.InvalidLoginCode)
  end
end
