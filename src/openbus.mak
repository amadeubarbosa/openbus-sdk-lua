PROJNAME= luaopenbus
LIBNAME= $(PROJNAME)

SRC= $(PRELOAD_DIR)/$(LIBNAME).c

OPENBUSIDL= ${OPENBUS_HOME}/idl/v2_00

LUADIR= ../lua
LUASRC= \
	$(LUADIR)/openbus/core/Access.lua \
	$(LUADIR)/openbus/core/idl/makeaux.lua \
	$(LUADIR)/openbus/core/idl/parsed.lua \
	$(LUADIR)/openbus/core/idl.lua \
	$(LUADIR)/openbus/core/messages.lua \
	$(LUADIR)/openbus/multiplexed.lua \
	$(LUADIR)/openbus/util/database.lua \
	$(LUADIR)/openbus/util/logger.lua \
	$(LUADIR)/openbus/util/messages.lua \
	$(LUADIR)/openbus/util/oo.lua \
	$(LUADIR)/openbus/util/server.lua \
	$(LUADIR)/openbus/util/sysex.lua \
	$(LUADIR)/openbus.lua

IDL= \
	$(OPENBUSIDL)/access_control.idl \
	$(OPENBUSIDL)/offer_registry.idl

include ${OIL_HOME}/openbus/base.mak

$(LUADIR)/openbus/core/idl/parsed.lua: $(IDL2LUA) $(IDL)
	$(OILBIN) $(IDL2LUA) -o $@ $(IDL)
