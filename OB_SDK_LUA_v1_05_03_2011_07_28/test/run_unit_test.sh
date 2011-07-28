#!/bin/ksh

PARAMS=$*

LATT_HOME=${OPENBUS_HOME}/lib/lua/5.1/latt

${OPENBUS_HOME}/bin/lua5.1 ${LATT_HOME}/extras/OiLTestRunner.lua ${PARAMS}
