#!/bin/bash

mode=$1
testcase=$2
services="server"

runconsole="source ${OPENBUS_SDKLUA_TEST}/runconsole.sh $mode"

if [[ "$mode" != "DEBUG" && "$mode" != "RELEASE" ]]; then
	echo "Usage: $0 <RELEASE|DEBUG> <test> [services...]"
	exit 1
fi

if [[ ${#@} > 2 ]]; then
	services="${@:3:${#@}}"
fi

cd $testcase
pid=
for service in $services; do
	echo "Starting service '$service' of test '$testcase'"
	$runconsole $service.lua $testcase &
	pid="$pid $!"
	trap "kill $pid > /dev/null 2>&1" 0
done

echo -n "Executing test '$testcase' ... "
$runconsole client.lua $testcase
echo "OK"
cd ../../test
echo -n "Test protocol with server of test '$testcase' ... "
$runconsole openbus/test/Protocol.lua
echo "OK"
cd ../interop
