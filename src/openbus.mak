PROJNAME= luaopenbus
LIBNAME= $(PROJNAME)

ifeq "$(TEC_SYSNAME)" "SunOS"
  USE_CC=Yes
  NO_LOCAL_LD=Yes
  AR=CC
  CFLAGS+= -KPIC
  STDLFLAGS= -xar
  CPPFLAGS= +p -KPIC -mt -D_REENTRANT
  ifeq ($(TEC_WORDSIZE), TEC_64)
    FLAGS+= -m64
    LFLAGS+= -m64
    STDLFLAGS+= -m64
  endif
  STDLFLAGS+= -o
endif

USE_LUA51= YES
NO_LUALINK=YES
USE_NODEPEND=YES

PRELOAD_DIR= ../obj/${TEC_UNAME}
INCLUDES= $(PRELOAD_DIR)

SRC= $(PRELOAD_DIR)/openbus.c

OPENBUSIDL= ${OPENBUS_HOME}/idl/v2_00

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

$(PRELOAD_DIR)/openbus.c: ${LOOP_HOME}/lua/preloader.lua $(LUAPCK)
	$(LUABIN) $< -l "$(LUADIR)/?.lua" -d $(PRELOAD_DIR) -h openbus.h -o openbus.c $(LUAPCK)
