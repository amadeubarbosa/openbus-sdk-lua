PROJNAME= OpenBus
LIBNAME= openbus

USE_LUA51= YES
USE_NODEPEND= YES

OPENBUSIDL= ${OPENBUS_HOME}/idlpath/v1_05

SRC= \
	openbuslibs.c \
	openbus.c

LUADIR= ../lua
LUA= \
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

ifeq "$(TEC_SYSNAME)" "Linux"
	LFLAGS = -Wl,-E
endif
ifeq "$(TEC_SYSNAME)" "SunOS"
	USE_CC=Yes
	CFLAGS= -g -KPIC -mt -D_REENTRANT
	ifeq ($(TEC_WORDSIZE), TEC_64)
		CFLAGS+= -m64
	endif
	LFLAGS= $(CFLAGS) -xildoff
	LIBS += rt
endif

$(LUADIR)/openbus/core/idl/parsed.lua: 
	$(LUABIN) ${OIL_HOME}/lua/idl2lua.lua -o $@ $^

openbuslibs.h: $(LUA)
	$(LUABIN) ${LOOP_HOME}/lua/precompiler.lua -l $(LUADIR)/?.lua -o $(basename $@) $^

openbus.h: openbuslibs.h
	$(LUABIN) ${LOOP_HOME}/lua/preloader.lua -o $(basename $@) $^

openbuslibs.c: openbuslibs.h
openbus.c: openbus.h
