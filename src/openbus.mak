PROJNAME= luaopenbus
LIBNAME= $(PROJNAME)

SRC= $(PRELOAD_DIR)/$(LIBNAME).c

OPENBUSSCSIDL= ${SCS_IDL1_2_HOME}/src
OPENBUSOLDIDL= ${OPENBUS_IDL1_5_HOME}/src
OPENBUSNEWIDL= ${OPENBUS_IDL2_0_HOME}/src
OPENBUSLIBIDL= ${SDK_IDL_SOURCE_HOME}/src

LUADIR= ../lua
LUASRC= \
  $(LUADIR)/openbus/assistant.lua \
  $(LUADIR)/openbus/assistant2.lua \
  $(LUADIR)/openbus/core/Access.lua \
  $(LUADIR)/openbus/core/idl/makeaux.lua \
  $(LUADIR)/openbus/core/idl/parsed.lua \
  $(LUADIR)/openbus/core/idl.lua \
  $(LUADIR)/openbus/core/legacy/idl.lua \
  $(LUADIR)/openbus/core/legacy/parsed.lua \
  $(LUADIR)/openbus/core/messages.lua \
  $(LUADIR)/openbus/idl/parsed.lua \
  $(LUADIR)/openbus/idl.lua \
  $(LUADIR)/openbus/util/argcheck.lua \
  $(LUADIR)/openbus/util/autotable.lua \
  $(LUADIR)/openbus/util/database.lua \
  $(LUADIR)/openbus/util/database_legacy.lua \
  $(LUADIR)/openbus/util/database_converter.lua \
  $(LUADIR)/openbus/util/except.lua \
  $(LUADIR)/openbus/util/logger.lua \
  $(LUADIR)/openbus/util/messages.lua \
  $(LUADIR)/openbus/util/oo.lua \
  $(LUADIR)/openbus/util/sandbox.lua \
  $(LUADIR)/openbus/util/server.lua \
  $(LUADIR)/openbus/util/sysex.lua \
  $(LUADIR)/openbus/util/tickets.lua \
  $(LUADIR)/openbus.lua

LIBIDL= $(OPENBUSLIBIDL)/openbus.idl

LIBDEPENDENTIDL= $(OPENBUSLIBIDL)/corba.idl

NEWIDL= \
  $(OPENBUSNEWIDL)/access_control.idl \
  $(OPENBUSNEWIDL)/offer_registry.idl \
  $(OPENBUSNEWIDL)/data_export.idl

NEWDEPENDENTIDL= \
  $(OPENBUSNEWIDL)/core.idl \
  $(OPENBUSNEWIDL)/credential.idl \
  $(OPENBUSSCSIDL)/scs.idl 
  
OLDIDL= \
  $(OPENBUSOLDIDL)/access_control_service.idl \
  $(OPENBUSOLDIDL)/registry_service.idl \
  $(OPENBUSOLDIDL)/fault_tolerance.idl

OLDDEPENDENTIDL= \
  $(OPENBUSOLDIDL)/core.idl \
  $(OPENBUSSCSIDL)/scs.idl

include ${OIL_HOME}/openbus/base.mak

$(LUADIR)/openbus/idl/parsed.lua: $(IDL2LUA) $(LIBIDL) $(NEWIDL) $(NEWDEPENDENTIDL) $(LIBDEPENDENTIDL)
	$(OILBIN) $(IDL2LUA) -I $(OPENBUSSCSIDL) -I $(OPENBUSNEWIDL) -I $(OPENBUSLIBIDL) -o $@ $(LIBIDL)

$(LUADIR)/openbus/core/idl/parsed.lua: $(IDL2LUA) $(NEWIDL) $(NEWDEPENDENTIDL)
	$(OILBIN) $(IDL2LUA) -I $(OPENBUSSCSIDL) -I $(OPENBUSNEWIDL) -o $@ $(NEWIDL)

$(LUADIR)/openbus/core/legacy/parsed.lua: $(IDL2LUA) $(OLDIDL) $(OLDDEPENDENTIDL)
	$(OILBIN) $(IDL2LUA) -I $(OPENBUSSCSIDL) -I $(OPENBUSOLDIDL) -o $@ $(OLDIDL)

openbuslua.c: $(PRELOAD_DIR)/luaopenbus.c

INTEROPIDLSDIR=../interop/lua/openbus/interop/idl

IDL_INTEROPS="BASIC" "CHAINING" "DELEGATION" "PROTOCOL"

$(INTEROPIDLSDIR):
	mkdir -p $(INTEROPIDLSDIR)
	for interop in $(IDL_INTEROPS) ; do \
	    lc_interop=`echo $$interop | tr A-Z a-z` ; \
	    eval path='$$'{OPENBUS_SDK_IDL_INTEROP_$${interop}_HOME} ; \
	    $(OILBIN) $(IDL2LUA) -o $(INTEROPIDLSDIR)/$${lc_interop}.lua `ls $$path/*.*` ; \
	done

parse-interops-idls: $(INTEROPIDLSDIR)
