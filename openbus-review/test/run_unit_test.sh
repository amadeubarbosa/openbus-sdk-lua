#!/bin/ksh

PARAMS=$*

LATT_HOME=${OPENBUS_HOME}/libpath/lua/5.1/latt

${OPENBUS_HOME}/core/bin/servicelauncher ${LATT_HOME}/extras/OiLTestRunner.lua ${PARAMS}
