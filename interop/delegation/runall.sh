#!/bin/bash

CONSOLE="${OPENBUS_HOME}/bin/busconsole"

SERVICES="\
messenger \
broadcaster \
forwarder \
"
pid=
for service in $SERVICES; do
  echo "Starting service '$service'"
  $CONSOLE $service.lua $@ &
  pid="$pid $!"
  trap "kill $pid > /dev/null 2> /dev/null" 0
done

echo -n "Executing test ... "
$CONSOLE client.lua $@
echo "OK"
