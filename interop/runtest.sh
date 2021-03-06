#!/bin/bash

mode=$1
testcase=$2
tasks=$3
services=$4

sdklua_interop=`dirname "$(readlink -f "$0")"`

busconsole="env LUA_PATH=${OPENBUS_SDKLUA_TEST}/?.lua;${sdklua_interop}/lua/?.lua ${OPENBUS_SDKLUA_HOME}/bin/busconsole"

if [[ "$mode" == "DEBUG" ]]; then
	busconsole="$busconsole -d"
elif [[ "$mode" != "RELEASE" ]]; then
	echo "Usage: $0 <RELEASE|DEBUG> <args>"
	exit 1
fi

# let all previous offers to expire
leasetime=`$busconsole -l openbus.test.configs -e 'print(leasetime)'`
sleep $leasetime
sleep $leasetime

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
	$busconsole $task.lua $testcase || exit $?
        echo "OK"
done

cd ../../test
echo -n "Test protocol with server of test '$testcase' ... "
$busconsole openbus/test/Protocol.lua || exit $?
echo "OK"
cd ../interop
