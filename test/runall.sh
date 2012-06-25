#!/bin/sh

CONSOLE="${OPENBUS_HOME}/bin/busconsole"
TESTDIR=${OPENBUS_HOME}/test

LUACASES="\
openbus/util/tickets \
openbus/util/database \
openbus/LoginLogout \
"
for case in ${LUACASES}; do
	echo -n "Test '${case}' ... "
	${CONSOLE} ${TESTDIR}/${case}.lua $@ || exit $?
	echo "OK"
done
