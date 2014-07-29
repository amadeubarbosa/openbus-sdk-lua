PROJNAME= luaopenbus
LIBNAME= $(PROJNAME)

SRC= $(PRELOAD_DIR)/$(LIBNAME).c

LUADIR= ../lua
LUASRC= \
  $(LUADIR)/openbus/assistant.lua \
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
  $(LUADIR)/openbus/util/corba.lua \
  $(LUADIR)/openbus/util/logger.lua \
  $(LUADIR)/openbus/util/messages.lua \
  $(LUADIR)/openbus/util/oo.lua \
  $(LUADIR)/openbus/util/server.lua \
  $(LUADIR)/openbus/util/sysex.lua \
  $(LUADIR)/openbus/util/tickets.lua \
  $(LUADIR)/openbus.lua

SCSIDL= $(OPENBUS_SCSIDL)/scs.idl

LIBIDL= $(OPENBUS_LIBIDL)/openbus.idl

NEWIDL= \
  $(OPENBUS_NEWIDL)/access_control.idl \
  $(OPENBUS_NEWIDL)/offer_registry.idl

OLDIDL= \
  $(OPENBUS_OLDIDL)/access_control_service.idl \
  $(OPENBUS_OLDIDL)/registry_service.idl \
  $(OPENBUS_OLDIDL)/fault_tolerance.idl

include ${OIL_HOME}/openbus/base.mak

$(LUADIR)/openbus/idl/parsed.lua: $(IDL2LUA) $(LIBIDL) $(NEWIDL) $(SCSIDL)
	$(OILBIN) $(IDL2LUA) -I $(OPENBUS_SCSIDL) -I $(OPENBUS_NEWIDL) -o $@ $(LIBIDL)

$(LUADIR)/openbus/core/idl/parsed.lua: $(IDL2LUA) $(NEWIDL) $(SCSIDL)
	$(OILBIN) $(IDL2LUA) -I $(OPENBUS_SCSIDL) -o $@ $(NEWIDL)

$(LUADIR)/openbus/core/legacy/parsed.lua: $(IDL2LUA) $(OLDIDL) $(SCSIDL)
	$(OILBIN) $(IDL2LUA) -I $(OPENBUS_SCSIDL) -o $@ $(OLDIDL)

$(PRELOAD_DIR)/$(LIBNAME).c: $(LUAPRELOADER) $(LUASRC)
	$(LOOPBIN) $(LUAPRELOADER) -m \
                             -l "$(LUADIR)/?.lua" \
                             -d $(PRELOAD_DIR) \
                             -h $(LIBNAME).h \
                             -o $(LIBNAME).c \
                             $(LUASRC)
