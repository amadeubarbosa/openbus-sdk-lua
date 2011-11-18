#!/bin/bash

OPENBUS_HOME=`pwd`/../../../install
export LD_LIBRARY_PATH="${OPENBUS_HOME}/lib:${LD_LIBRARY_PATH}"
export LUA_PATH=";;${OPENBUS_HOME}/../lib/sdk-lua/lua/?.lua;${OPENBUS_HOME}/../svn/lua/?.lua;${OPENBUS_HOME}/test/?.lua;${OPENBUS_HOME}/lib/lua/5.1/?.lua"

PARAMS=$*

LATT_HOME=${OPENBUS_HOME}/lib/lua/5.1/latt

${OPENBUS_HOME}/bin/busconsole -d ${LATT_HOME}/ConsoleTestRunner.lua ${PARAMS}

