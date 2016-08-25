#!/bin/bash

mode=$1

runconsole="source ${OPENBUS_SDKLUA_TEST}/runconsole.sh $mode"

if [[ "$mode" != "DEBUG" && "$mode" != "RELEASE" ]]; then
	echo "Usage: $0 <RELEASE|DEBUG>"
	exit 1
fi

cases="\
openbus/test/util/tickets \
openbus/test/NoLoginIceptorCalls \
openbus/test/Concurrency \
openbus/test/OnCallDispatch \
openbus/test/MakeChainFor \
openbus/test/ImportChain \
openbus/test/ChainExport \
openbus/test/LoginLogout \
openbus/test/assistant/Concurrency \
openbus/test/assistant/NoLoginIceptorCalls \
openbus/test/assistant/LoginLogout \
openbus/test/assistant/AssistantLoginLogout \
"
for case in $cases; do
	echo -n "Test '${case}' ... "
	$runconsole $case.lua ${@:2:${#@}} || exit $?
	echo "OK"
done
