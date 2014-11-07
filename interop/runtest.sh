#!/bin/bash

CONSOLE="${OPENBUS_HOME}/bin/busconsole"

if [ "$1" == "DEBUG" ]; then
	CONSOLE="$CONSOLE -d"
elif [ "$1" != "RELEASE" ]; then
	echo "Usage: runtest.sh [RELEASE|DEBUG] <dir> [services]"
	exit 1
fi

if [[ ${#@} > 2 ]]; then
	services="${@:3:${#@}}"
else
	services="server"
fi

cd $2
pid=
for service in $services; do
	echo "Starting service '$service' of test '$2'"
	$CONSOLE $service.lua $2 &
	pid="$pid $!"
	trap "kill $pid > /dev/null 2> /dev/null" 0
done

echo -n "Executing test '$2' ... "
$CONSOLE client.lua $2
echo "OK"
cd ../../test
echo -n "Test protocol with server of test '$2' ... "
$CONSOLE openbus/test/Protocol.lua
echo "OK"
cd ../interop
