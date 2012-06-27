PROJNAME= luaopenbus
LIBNAME= $(PROJNAME)

SRC= $(PRELOAD_DIR)/$(LIBNAME).c

OPENBUSOLDIDL= ${OPENBUS_HOME}/idl/v1_05
OPENBUSNEWIDL= ${OPENBUS_HOME}/idl/v2_00

LUADIR= ../lua
LUASRC= \
  $(LUADIR)/openbus/core/Access.lua \
  $(LUADIR)/openbus/core/idl/makeaux.lua \
  $(LUADIR)/openbus/core/idl/parsed.lua \
  $(LUADIR)/openbus/core/idl.lua \
  $(LUADIR)/openbus/core/legacy/parsed.lua \
  $(LUADIR)/openbus/core/legacy/idl.lua \
  $(LUADIR)/openbus/core/messages.lua \
  $(LUADIR)/openbus/util/argcheck.lua \
  $(LUADIR)/openbus/util/autotable.lua \
  $(LUADIR)/openbus/util/database.lua \
  $(LUADIR)/openbus/util/logger.lua \
  $(LUADIR)/openbus/util/messages.lua \
  $(LUADIR)/openbus/util/oo.lua \
  $(LUADIR)/openbus/util/server.lua \
  $(LUADIR)/openbus/util/sysex.lua \
  $(LUADIR)/openbus/util/tickets.lua \
  $(LUADIR)/openbus.lua

NEWIDL= \
  $(OPENBUSNEWIDL)/access_control.idl \
  $(OPENBUSNEWIDL)/offer_registry.idl

OLDIDL= \
  $(OPENBUSOLDIDL)/access_control_service.idl \
  $(OPENBUSOLDIDL)/registry_service.idl \
  $(OPENBUSOLDIDL)/fault_tolerance.idl

include ${OIL_HOME}/openbus/base.mak

$(LUADIR)/openbus/core/idl/parsed.lua: $(IDL2LUA) $(NEWIDL)
	$(OILBIN) $(IDL2LUA) -o $@ $(NEWIDL)

$(LUADIR)/openbus/core/legacy/parsed.lua: $(IDL2LUA) $(OLDIDL)
	$(OILBIN) $(IDL2LUA) -o $@ $(OLDIDL)

$(PRELOAD_DIR)/$(LIBNAME).c: $(LUAPRELOADER) $(LUASRC)
	$(LOOPBIN) $(LUAPRELOADER) -m \
                             -l "$(LUADIR)/?.lua" \
                             -d $(PRELOAD_DIR) \
                             -h $(LIBNAME).h \
                             -o $(LIBNAME).c \
                             $(LUASRC)
