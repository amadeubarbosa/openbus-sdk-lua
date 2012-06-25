#!/bin/bash

CONSOLE="${OPENBUS_HOME}/bin/busconsole"

LUACASES="\
openbus/util/tickets \
openbus/util/database \
openbus/LoginLogout \
"
for case in ${LUACASES}; do
	echo -n "Test '${case}' ... "
	${CONSOLE} ${case}.lua $@ || exit $?
	echo "OK"
done
