#!/bin/bash

mode=$1
testcase=$2
services="server"

busconsole="env LUA_PATH=${OPENBUS_SDKLUA_TEST}/?.lua ${OPENBUS_SDKLUA_HOME}/bin/busconsole"

if [[ "$mode" == "DEBUG" ]]; then
	busconsole="$busconsole -d"
elif [[ "$mode" != "RELEASE" ]]; then
	echo "Usage: $0 <RELEASE|DEBUG> <args>"
	exit 1
fi

if [[ ${#@} > 2 ]]; then
	services="${@:3:${#@}}"
fi

cd $testcase
pid=
for service in $services; do
	echo "Starting service '$service' of test '$testcase'"
	$busconsole $service.lua $testcase &
	pid="$pid $!"
	trap "kill $pid > /dev/null 2>&1" 0
done

echo -n "Executing test '$testcase' ... "
$busconsole client.lua $testcase
echo "OK"
cd ../../test
echo -n "Test protocol with server of test '$testcase' ... "
$busconsole openbus/test/Protocol.lua
echo "OK"
cd ../interop
