#!/bin/bash

mode=$1

if [[ "$mode" == "" ]]; then
	mode=RELEASE
elif [[ "$mode" != "RELEASE" && "$mode" != "DEBUG" ]]; then
	echo "Usage: $0 [RELEASE|DEBUG]"
	exit 1
fi

bus1port=21210
bus2port=21212
leasetime=1
passwordpenalty=1

export OPENBUS_TESTCFG=$OPENBUS_TEMP/test.properties
echo "bus.host.port=$bus1port"                 > $OPENBUS_TESTCFG
echo "bus2.host.port=$bus2port"               >> $OPENBUS_TESTCFG
echo "login.lease.time=$leasetime"            >> $OPENBUS_TESTCFG
echo "password.penalty.time=$passwordpenalty" >> $OPENBUS_TESTCFG
#echo "openbus.test.verbose=yes"               >> $OPENBUS_TESTCFG

runbus="source ${OPENBUS_CORE_TEST}/runbus.sh $mode"
runadmin="source ${OPENBUS_CORE_TEST}/runadmin.sh $mode"

$runbus BUS01 $bus1port
$runbus BUS02 $bus2port
genkey $OPENBUS_TEMP/testsyst

$runadmin localhost $bus1port --script=${OPENBUS_CORE_TEST}/test.adm
$runadmin localhost $bus2port --script=${OPENBUS_CORE_TEST}/test.adm
source runtests.sh $mode
$runadmin localhost $bus1port --undo-script=${OPENBUS_CORE_TEST}/test.adm
$runadmin localhost $bus2port --undo-script=${OPENBUS_CORE_TEST}/test.adm

cd ../interop
$runadmin localhost $bus1port --script=script.adm
$runadmin localhost $bus2port --script=script.adm
source runall.sh $mode
sleep 2 # wait for offers to expire
$runadmin localhost $bus1port --undo-script=script.adm
$runadmin localhost $bus2port --undo-script=script.adm
cd ../test
