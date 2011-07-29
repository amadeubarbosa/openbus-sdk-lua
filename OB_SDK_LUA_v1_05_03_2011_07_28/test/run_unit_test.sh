#!/bin/ksh

OPENBUS_DATADIR=${OPENBUS_DATADIR:=$OPENBUS_HOME/data}
export OPENBUS_DATADIR

CONFIG=${OPENBUS_DATADIR}/conf/config

if [ -f "${CONFIG}" ]; then
  source ${CONFIG}
fi

PARAMS=$*

LATT_HOME=${OPENBUS_HOME}/lib/lua/5.1/latt

${OPENBUS_HOME}/bin/lua5.1 ${LATT_HOME}/extras/OiLTestRunner.lua ${PARAMS}
