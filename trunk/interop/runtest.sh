#!/bin/bash

mode=$1
testcase=$2
tasks=$3
services=$4

busconsole="${OPENBUS_SDKLUA_HOME}/bin/busconsole"

if [[ "$mode" == "DEBUG" ]]; then
	busconsole="$busconsole DEBUG"
elif [[ "$mode" != "RELEASE" ]]; then
	echo "Usage: $0 <RELEASE|DEBUG> <tasks> <services>"
	exit 1
fi

cd $testcase
pid=
for service in $services; do
	echo "Starting service '$service' of test '$testcase'"
	$busconsole $service.lua $testcase &
	pid="$pid $!"
	trap "kill $pid > /dev/null 2>&1" 0
done

for task in $tasks; do
	echo -n "Executing task '$task' of test '$testcase' ... "
	$busconsole $task.lua $testcase
	echo "OK"
done

cd ../../test
echo -n "Test protocol with server of test '$testcase' ... "
$busconsole openbus/test/Protocol.lua
echo "OK"
cd ../interop
