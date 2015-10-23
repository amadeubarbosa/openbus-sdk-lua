#!/bin/bash

mode=$1

busconsole="env LUA_PATH=${OPENBUS_SDKLUA_TEST}/?.lua ${OPENBUS_SDKLUA_HOME}/bin/busconsole"

if [[ "$mode" != "DEBUG" && "$mode" != "RELEASE" ]]; then
	echo "Usage: $0 <RELEASE|DEBUG> <args>"
	exit 1
fi

$busconsole "${@:2:${#@}}" || exit $?
