#!/bin/bash

CONSOLE="${OPENBUS_HOME}/bin/busconsole"

echo "Starting service"
$CONSOLE server.lua $@ &
pid="$pid $!"
trap "kill $pid > /dev/null 2> /dev/null" 0

echo -n "Executing test ... "
$CONSOLE client.lua $@
echo "OK"
