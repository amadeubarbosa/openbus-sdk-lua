PROJNAME= OpenBus
LIBNAME= openbus

USE_LUA51= YES

OPENBUSIDL= ${OPENBUS_HOME}/idlpath/v2_00

SRC= openbus.c

LUADIR= ../lua
LUAPCK= $(addprefix $(LUADIR)/, \
	openbus/core/Access.lua \
	openbus/core/idl/makeaux.lua \
	openbus/core/idl/parsed.lua \
	openbus/core/idl.lua \
	openbus/core/messages.lua \
	openbus/multiplexed.lua \
	openbus/util/database.lua \
	openbus/util/logger.lua \
	openbus/util/messages.lua \
	openbus/util/oo.lua \
	openbus/util/server.lua \
	openbus/util/sysex.lua \
	openbus.lua )

IDL= $(addprefix $(OPENBUSIDL)/, \
	access_control.idl \
	offer_registry.idl )

$(LUADIR)/openbus/core/idl/parsed.lua: ${OIL_HOME}/lua/idl2lua.lua $(IDL)
	$(LUABIN) $< -o $@ $(filter-out $<,$^)

openbus.c: ${LOOP_HOME}/lua/preloader.lua $(LUAPCK)
	$(LUABIN) $< -l "$(LUADIR)/?.lua" -h $(@:.c=.h) -o $@ $(filter-out $<,$^)
