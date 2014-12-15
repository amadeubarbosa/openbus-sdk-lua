#!/bin/bash

mode=$1

if [[ "$mode" == "" ]]; then
	mode=RELEASE
elif [[ "$mode" != "RELEASE" && "$mode" != "DEBUG" ]]; then
	echo "Usage: $0 <RELEASE|DEBUG>"
	exit 1
fi

bus1port=20011
bus2port=20021
leasetime=1
passwordpenalty=1

export OPENBUS_TESTCFG=$OPENBUS_TEMP/test.properties
echo "bus.host.port=$bus1port"                 > $OPENBUS_TESTCFG
echo "bus2.host.port=$bus2port"               >> $OPENBUS_TESTCFG
echo "login.lease.time=$leasetime"            >> $OPENBUS_TESTCFG
echo "password.penalty.time=$passwordpenalty" >> $OPENBUS_TESTCFG
#echo "openbus.test.verbose=yes"               >> $OPENBUS_TESTCFG

source ${OPENBUS_CORE_TEST}/runbus.sh $mode BUS01 $bus1port
source ${OPENBUS_CORE_TEST}/runbus.sh $mode BUS02 $bus2port
genkey $OPENBUS_TEMP/testsyst

source ${OPENBUS_CORE_TEST}/runadmin.sh $mode localhost $bus1port --script=${OPENBUS_CORE_TEST}/test.adm
source ${OPENBUS_CORE_TEST}/runadmin.sh $mode localhost $bus2port --script=${OPENBUS_CORE_TEST}/test.adm
source runtests.sh $mode
source ${OPENBUS_CORE_TEST}/runadmin.sh $mode localhost $bus1port --undo-script=${OPENBUS_CORE_TEST}/test.adm
source ${OPENBUS_CORE_TEST}/runadmin.sh $mode localhost $bus2port --undo-script=${OPENBUS_CORE_TEST}/test.adm

cd ../interop
source ${OPENBUS_CORE_TEST}/runadmin.sh $mode localhost $bus1port --script=script.adm
source ${OPENBUS_CORE_TEST}/runadmin.sh $mode localhost $bus2port --script=script.adm
source runall.sh $mode
sleep 2 # wait for offers to expire
source ${OPENBUS_CORE_TEST}/runadmin.sh $mode localhost $bus1port --undo-script=script.adm
source ${OPENBUS_CORE_TEST}/runadmin.sh $mode localhost $bus2port --undo-script=script.adm
cd ../test
