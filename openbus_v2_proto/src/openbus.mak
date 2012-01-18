PROJNAME= luaopenbus
LIBNAME= $(PROJNAME)

SRC= \
	$(PRELOAD_DIR)/$(LIBNAME).c \
	strbitwise.c

OPENBUSIDL= ${OPENBUS_HOME}/idl/v2_00

LUAMOD= \
	openbus.core.Access \
	openbus.core.idl.makeaux \
	openbus.core.idl.parsed \
	openbus.core.idl \
	openbus.core.messages \
	openbus.multiplexed \
	openbus.util.argcheck \
	openbus.util.autotable \
	openbus.util.cache \
	openbus.util.database \
	openbus.util.logger \
	openbus.util.messages \
	openbus.util.oo \
	openbus.util.server \
	openbus.util.sysex \
	openbus.util.tickets \
	openbus
LUADIR= ../lua
LUASRC=$(addprefix $(LUADIR)/,$(addsuffix .lua,$(subst .,/,$(LUAMOD))))

IDL= \
	$(OPENBUSIDL)/credential.idl \
	$(OPENBUSIDL)/offer_registry.idl

include ${OIL_HOME}/openbus/base.mak

$(LUADIR)/openbus/core/idl/parsed.lua: $(IDL2LUA) $(IDL)
	$(OILBIN) $(IDL2LUA) -o $@ $(IDL)

$(PRELOAD_DIR)/$(LIBNAME).c: $(LUAPRELOADER) $(LUASRC)
	$(LOOPBIN) $(LUAPRELOADER) -m -n \
	                           -l "$(LUADIR)/?.lua" \
	                           -d $(PRELOAD_DIR) \
	                           -h $(LIBNAME).h \
	                           -o $(LIBNAME).c \
	                           string.bitwise $(LUAMOD)
