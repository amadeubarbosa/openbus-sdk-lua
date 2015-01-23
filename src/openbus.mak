PROJNAME= luaopenbus
LIBNAME= $(PROJNAME)

SRC= \
  openbuslua.c \
  lecholib.c \
  lthreadlib.c \
  $(PRELOAD_DIR)/$(LIBNAME).c

OPENBUSSCSIDL= ${SCS_IDL1_2_HOME}/src
OPENBUSNEWIDL= ${OPENBUS_IDL2_1_HOME}/src
OPENBUSOLDIDL= ${OPENBUS_IDL2_0_HOME}/src
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
  $(LUADIR)/openbus/util/except.lua \
  $(LUADIR)/openbus/util/logger.lua \
  $(LUADIR)/openbus/util/messages.lua \
  $(LUADIR)/openbus/util/oo.lua \
  $(LUADIR)/openbus/util/sandbox.lua \
  $(LUADIR)/openbus/util/server.lua \
  $(LUADIR)/openbus/util/sysex.lua \
  $(LUADIR)/openbus/util/tickets.lua \
  $(LUADIR)/openbus.lua \
  lecholib.c \
  lthreadlib.c \
  $(LUADIR)/openbus/console/costdin.lua \
  $(LUADIR)/openbus/console/utils.lua

LIBIDL= $(OPENBUSLIBIDL)/openbus.idl

LIBDEPENDENTIDL= $(OPENBUSLIBIDL)/corba.idl

NEWIDL= \
  $(OPENBUSNEWIDL)/tecgraf/openbus/core/v2_1/services/access_control.idl \
  $(OPENBUSNEWIDL)/tecgraf/openbus/core/v2_1/services/offer_registry.idl \
  $(OPENBUSNEWIDL)/tecgraf/openbus/core/v2_1/data_export.idl

NEWDEPENDENTIDL= \
  $(OPENBUSNEWIDL)/tecgraf/openbus/core/v2_1/core.idl \
  $(OPENBUSNEWIDL)/tecgraf/openbus/core/v2_1/credential.idl \
  $(OPENBUSSCSIDL)/scs.idl 
  
OLDIDL= \
  $(OPENBUSNEWIDL)/tecgraf/openbus/core/v2_1/services/legacy_support.idl \
  $(OPENBUSOLDIDL)/access_control.idl \
  $(OPENBUSOLDIDL)/offer_registry.idl \
  $(OPENBUSOLDIDL)/data_export.idl

OLDDEPENDENTIDL= \
  $(OPENBUSNEWIDL)/tecgraf/openbus/core/v2_1/services/access_control.idl \
  $(OPENBUSNEWIDL)/tecgraf/openbus/core/v2_1/core.idl \
  $(OPENBUSNEWIDL)/tecgraf/openbus/core/v2_1/credential.idl \
  $(OPENBUSOLDIDL)/core.idl \
  $(OPENBUSOLDIDL)/credential.idl \
  $(OPENBUSSCSIDL)/scs.idl

LUAPRELOADFLAGS= -s

include ${OIL_HOME}/openbus/base.mak

LIBS:= \
  luastruct \
  luasocket \
  luatuple \
  loop \
  luacothread \
  luaidl \
  oil \
  luavararg \
  lfs \
  luuid \
  lce \
  luasec \
  luascs

INCLUDES+= . \
  $(LUASTRUCT_HOME)/src \
  $(LUASOCKET_HOME)/include \
  $(LUATUPLE_HOME)/obj/$(TEC_UNAME) \
  $(LOOP_HOME)/obj/$(TEC_UNAME) \
  $(LUACOTHREAD_HOME)/obj/$(TEC_UNAME) \
  $(LUAIDL_HOME)/obj/$(TEC_UNAME) \
  $(OIL_HOME)/obj/$(TEC_UNAME) \
  $(LUAVARARG_HOME)/src \
  $(LUAFILESYSTEM_HOME)/include \
  $(LUUID_HOME)/include \
  $(LCE_HOME)/include \
  $(LUASEC_HOME)/include \
  $(SCS_LUA_HOME)/obj/$(TEC_UNAME)

LDIR+= \
  $(LUASTRUCT_HOME)/lib/$(TEC_UNAME) \
  $(LUASOCKET_HOME)/lib/$(TEC_UNAME) \
  $(LUATUPLE_HOME)/lib/$(TEC_UNAME) \
  $(LOOP_HOME)/lib/$(TEC_UNAME) \
  $(LUACOTHREAD_HOME)/lib/$(TEC_UNAME) \
  $(LUAIDL_HOME)/lib/$(TEC_UNAME) \
  $(OIL_HOME)/lib/$(TEC_UNAME) \
  $(LUAVARARG_HOME)/lib/$(TEC_UNAME) \
  $(LUAFILESYSTEM_HOME)/lib/$(TEC_UNAME) \
  $(LUUID_HOME)/lib/$(TEC_UNAME) \
  $(LCE_HOME)/lib/$(TEC_UNAME) \
  $(LUASEC_HOME)/lib/$(TEC_UNAME) \
  $(SCS_LUA_HOME)/lib/$(TEC_UNAME)

$(LUADIR)/openbus/idl/parsed.lua: $(IDL2LUA) $(LIBIDL) $(NEWIDL) $(NEWDEPENDENTIDL) $(LIBDEPENDENTIDL)
	$(OILBIN) $(IDL2LUA) -I $(OPENBUSSCSIDL) -I $(OPENBUSNEWIDL) -I $(OPENBUSLIBIDL) -o $@ $(LIBIDL)

$(LUADIR)/openbus/core/idl/parsed.lua: $(IDL2LUA) $(NEWIDL) $(NEWDEPENDENTIDL)
	$(OILBIN) $(IDL2LUA) -I $(OPENBUSSCSIDL) -I $(OPENBUSNEWIDL) -o $@ $(NEWIDL)

$(LUADIR)/openbus/core/legacy/parsed.lua: $(IDL2LUA) $(OLDIDL) $(OLDDEPENDENTIDL)
	$(OILBIN) $(IDL2LUA) -I $(OPENBUSSCSIDL) -I $(OPENBUSOLDIDL) -I $(OPENBUSNEWIDL) -o $@ $(OLDIDL)

openbuslua.c: $(PRELOAD_DIR)/luaopenbus.c
