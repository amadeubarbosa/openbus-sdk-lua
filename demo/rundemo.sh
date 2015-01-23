#!/bin/bash

BUSHOST=localhost
BUSPORT=2089
SYSTEM=testsyst
KEYPATH=$(dirname $OPENBUS_TESTCFG)/testsyst.key
USER=testuser
DOMAIN=testing
PASSWORD=$USER

CONSOLE="${OPENBUS_HOME}/bin/busconsole"

if [ "$1" == "DEBUG" ]; then
	CONSOLE="$CONSOLE DEBUG"
elif [ "$1" != "RELEASE" ]; then
	echo "Usage: runtest.sh [RELEASE|DEBUG] <dir> [services]"
	exit 1
fi

pid=
for service in server proxy; do
	if [[ -e $2/$service.lua ]]; then
		echo -n "Starting service '$service' of demo '$2' "
		$CONSOLE $2/$service.lua $BUSHOST $BUSPORT $SYSTEM $KEYPATH &
		pid="$pid $!"
		trap "kill $pid > /dev/null 2> /dev/null" 0
		# wait service to be ready
		for (( i = 0; i < 3; ++i )); do
			echo -n "."
			sleep 1
		done
		echo ""
	fi
done

echo "Executing demo '$2' ... "
$CONSOLE $2/client.lua $BUSHOST $BUSPORT $USER $DOMAIN $PASSWORD
