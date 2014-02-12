PROJNAME= busconsole
APPNAME= $(PROJNAME)

ifdef USE_LUA52
	SRC= console.c
else
	SRC= consoleLua51.c
endif

LIBS:= lce luuid lfs luavararg luastruct luasocket loop luatuple \
  luacoroutine luacothread luainspector luaidl oil luascs luaopenbus

INCLUDES+= . $(SRCLUADIR) \
  $(LCE_HOME)/include \
  $(LUUID_HOME)/include \
  $(LUAFILESYSTEM_HOME)/include \
  $(LUASOCKET_HOME)/include \
  $(LUASTRUCT_HOME)/src \
  $(LUAVARARG_HOME)/src \
  $(LUAINSPECTOR_HOME)/obj/$(TEC_UNAME) \
  $(LUATUPLE_HOME)/obj/$(TEC_UNAME) \
  $(LUACOROUTINE_HOME)/obj/$(TEC_UNAME) \
  $(LUACOTHREAD_HOME)/obj/$(TEC_UNAME) \
  $(LOOP_HOME)/obj/$(TEC_UNAME) \
  $(LUAIDL_HOME)/obj/$(TEC_UNAME) \
  $(OIL_HOME)/obj/$(TEC_UNAME) \
  $(SCS_LUA_HOME)/obj/$(TEC_UNAME) \
  $(OPENBUS_LUA_HOME)/obj/$(TEC_UNAME)
LDIR+= \
  $(LCE_HOME)/lib/$(TEC_UNAME) \
  $(LUUID_HOME)/lib/$(TEC_UNAME) \
  $(LUAFILESYSTEM_HOME)/lib/$(TEC_UNAME) \
  $(LUASOCKET_HOME)/lib/$(TEC_UNAME) \
  $(LUASTRUCT_HOME)/lib/$(TEC_UNAME) \
  $(LUAVARARG_HOME)/lib/$(TEC_UNAME) \
  $(LUAINSPECTOR_HOME)/lib/$(TEC_UNAME) \
  $(LUATUPLE_HOME)/lib/$(TEC_UNAME) \
  $(LUACOROUTINE_HOME)/lib/$(TEC_UNAME) \
  $(LUACOTHREAD_HOME)/lib/$(TEC_UNAME) \
  $(LUAIDL_HOME)/lib/$(TEC_UNAME) \
  $(LOOP_HOME)/lib/$(TEC_UNAME) \
  $(OIL_HOME)/lib/$(TEC_UNAME) \
  $(SCS_LUA_HOME)/lib/$(TEC_UNAME) \
  $(OPENBUS_LUA_HOME)/lib/$(TEC_UNAME)

ifdef USE_LUA51
  INCLUDES+= $(LUACOMPAT52_HOME)/c-api $(LUACOMPAT52_HOME)/obj/$(TEC_UNAME)
  LDIR+= $(LUACOMPAT52_HOME)/lib/$(TEC_UNAME)
  LIBS+= luacompat52 luabit32 luacompat52c
endif

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
endif

ifdef USE_STATIC
  SLIB:= $(foreach libname, $(LIBS) uuid crypto, ${OPENBUS_HOME}/lib/lib$(libname).a)
  ifeq "$(TEC_SYSNAME)" "SunOS"
    LIBS:= rt nsl socket resolv
  else
    LIBS:= 
  endif
else
  ifeq ($(findstring $(TEC_SYSNAME), Win32 Win64), )
    ifneq "$(TEC_SYSNAME)" "Darwin"
      LIBS+= uuid
    endif
  endif
endif

ifneq ($(findstring $(TEC_SYSNAME), Win32 Win64), )
  APPTYPE= console
  LIBS+= wsock32 rpcrt4
  ifneq ($(findstring dll, $(TEC_UNAME)), ) # USE_DLL
    ifdef DBG
      LIBS+= libeay32MDd ssleay32MDd
    else
      LIBS+= libeay32MD ssleay32MD
    endif
    LDIR+= $(OPENSSL_HOME)/lib/VC
  else
    ifdef DBG
      LIBS+= libeay32MTd ssleay32MTd
    else
      LIBS+= libeay32MT ssleay32MT
    endif
    LDIR+= $(OPENSSL_HOME)/lib/VC/static
  endif
else
  LIBS+= dl
endif
