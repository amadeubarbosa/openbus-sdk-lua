PROJNAME=openbuslua
LIBNAME=${PROJNAME}

# tecmake directories where it puts objects and libraries
#OBJROOT= obj
#TARGETROOT= lib

LUABIN= ${LUA51}/bin/${TEC_UNAME}/lua5.1
LUAPATH = '${OPENBUS_HOME}/libpath/lua/5.1/?.lua;./?.lua;../../?.lua;'

OPENBUSLIB= ${OPENBUS_HOME}/libpath/${TEC_UNAME} 
OPENBUSINC= ${OPENBUS_HOME}/incpath

PRECMP_DIR= ../obj/${TEC_UNAME}
PRECMP_LUA= ${OPENBUS_HOME}/libpath/lua/5.1/precompiler.lua
PRECMP_FLAGS= -p OPENBUS_API -o openbus -l ${LUAPATH} -d ${PRECMP_DIR} -n

PRELOAD_LUA= ${OPENBUS_HOME}/libpath/lua/5.1/preloader.lua
PRELOAD_FLAGS= -p OPENBUS_API -o openbuspreloaded -d ${PRECMP_DIR}

OPENBUS_MODULES=$(addprefix openbus.,\
	Openbus \
	authenticators.Authenticator \
	authenticators.CertificateAuthenticator \
	authenticators.LoginPasswordAuthenticator \
	faulttolerance.ServiceStatusManager \
	faulttolerance.SmartComponent \
	faulttolerance.smartpatch \
	interceptors.ClientInterceptor \
	interceptors.PICurrent \
	interceptors.ServerInterceptor \
	lease.LeaseProvider \
	lease.LeaseRenewer \
	util.CredentialManager \
	util.Log \
	util.OilUtilities \
	util.TableDB \
	util.Utils )

OPENBUS_LUA= \
  $(addsuffix .lua, \
    $(subst .,/, $(OPENBUS_MODULES)))

${PRECMP_DIR}/openbus.c: ${OPENBUS_LUA}
	$(LUABIN) $(LUA_FLAGS) $(PRECMP_LUA)   $(PRECMP_FLAGS) $(OPENBUS_MODULES) 

${PRECMP_DIR}/openbuspreloaded.c: ${PRECMP_DIR}/openbus.c
	$(LUABIN) $(LUA_FLAGS) $(PRELOAD_LUA)  $(PRELOAD_FLAGS) -i ${PRECMP_DIR} openbus.h

#Descomente a linha abaixo caso deseje ativar o VERBOSE
#DEFINES=VERBOSE

SRC= ${PRECMP_DIR}/openbus.c ${PRECMP_DIR}/openbuspreloaded.c

INCLUDES= . ${PRECMP_DIR}
LDIR += ${OPENBUSLIB}

USE_LUA51=YES
NO_LUALINK=YES
USE_NODEPEND=YES

#############################
# Usa bibliotecas dinâmicas #
#############################

LIBS= dl

ifeq "$(TEC_SYSNAME)" "SunOS"
  USE_CC=Yes
  CFLAGS= -g -KPIC -mt -D_REENTRANT
  ifeq ($(TEC_WORDSIZE), TEC_64)
    CFLAGS+= -m64
  endif
endif

.PHONY: clean-custom 
clean-custom-obj:
	rm -f ${PRECMP_DIR}/*.c
	rm -f ${PRECMP_DIR}/*.h
