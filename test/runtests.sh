#!/bin/bash

mode=$1

busconsole="${OPENBUS_SDKLUA_HOME}/bin/busconsole"

if [[ "$mode" == "DEBUG" ]]; then
	busconsole="$busconsole -d"
elif [[ "$mode" != "RELEASE" ]]; then
	echo "Usage: $0 <RELEASE|DEBUG>"
	exit 1
fi

cases="\
openbus/test/util/tickets \
openbus/test/util/database \
openbus/test/NoLoginIceptorCalls \
openbus/test/Concurrency \
openbus/test/MakeChainFor \
openbus/test/ChainExport \
openbus/test/LoginLogout \
openbus/test/assistant/Concurrency \
openbus/test/assistant/NoLoginIceptorCalls \
openbus/test/assistant/LoginLogout \
openbus/test/assistant/AssistantLoginLogout \
"
for case in $cases; do
	echo -n "Test '${case}' ... "
	$busconsole $case.lua ${@:2:${#@}} || exit $?
	echo "OK"
done
