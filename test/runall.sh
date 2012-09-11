#!/bin/bash

CONSOLE="${OPENBUS_HOME}/bin/busconsole"

if [ "$1" == "DEBUG" ]; then
	CONSOLE="$CONSOLE -d"
elif [ "$1" != "RELEASE" ]; then
	echo "Usage: runall.sh [RELEASE|DEBUG] bushost busport [verbose]"
	exit 1
fi

LUACASES="\
openbus/test/util/tickets \
openbus/test/util/database \
openbus/test/LoginLogout \
openbus/test/Concurrency \
openbus/test/NoLoginIceptorCalls \
"
for case in ${LUACASES}; do
	echo -n "Test '${case}' ... "
	${CONSOLE} ${case}.lua ${@:2:${#@}} || exit $?
	echo "OK"
done