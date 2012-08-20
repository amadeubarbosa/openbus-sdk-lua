PROJNAME= busconsole
APPNAME= $(PROJNAME)

USE_LUA51= YES

OPENBUSINC= ${OPENBUS_HOME}/include
OPENBUSLIB= ${OPENBUS_HOME}/lib

SRC= console.c

LIBS:= lce luuid lfs luavararg luastruct  luasocket loop luatuple \
  luacoroutine luacothread luainspector luaidl oil luascs luaopenbus lua5.1

INCLUDES+= . $(SRCLUADIR) \
  $(OPENBUSINC)/luuid \
  $(OPENBUSINC)/lce \
  $(OPENBUSINC)/luafilesystem \
  $(OPENBUSINC)/luavararg \
  $(OPENBUSINC)/luastruct \
  $(OPENBUSINC)/luasocket2 \
  $(OPENBUSINC)/loop \
  $(OPENBUSINC)/oil \
  $(OPENBUSINC)/scs/lua \
  $(OPENBUSINC)/openbus/lua
LDIR+= $(OPENBUSLIB)

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
  SLIB:= $(foreach libname, $(LIBS) uuid crypto, $(OPENBUSLIB)/lib$(libname).a)
  ifeq "$(TEC_SYSNAME)" "SunOS"
    LIBS:= rt nsl socket resolv
  else
    LIBS:= 
  endif
else
  ifneq "$(TEC_SYSNAME)" "Darwin"
    LIBS+= uuid
  endif
endif

LIBS+= dl
