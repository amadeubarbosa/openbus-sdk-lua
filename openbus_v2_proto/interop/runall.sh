#!/bin/bash

CORESERV="${OPENBUS_HOME}/bin/busservices DEBUG"
echo "Starting core bus services"
if [ -d openbus.db ]; then
  INITBUS=no
fi
$CORESERV -leasetime 1 \
          -expirationgap .5 \
          -admin admin \
          -validator openbus.test.core.services.TesterUserValidator &
pid="$pid $!"
trap "kill $pid > /dev/null 2> /dev/null" 0

echo "Starting second core bus services"
if [ -d openbus2.db ]; then
  INITBUS2=no
fi
$CORESERV -port 2090 \
          -database openbus2.db \
          -leasetime 1 \
          -expirationgap .5 \
          -admin admin \
          -validator openbus.test.core.services.TesterUserValidator &
pid="$pid $!"
trap "kill $pid > /dev/null 2> /dev/null" 0



echo "Waiting core bus services to be accessible"
CONSOLE="${OPENBUS_HOME}/bin/busconsole -d"
$CONSOLE -l oil -e '
for _, port in ipairs{2089,2090} do
  local bus = oil.init():newproxy("corbaloc::localhost:"..port.."/OpenBus_2_0",
                                  nil, oil.corba.idl.object)
  while bus:_non_existent() do
    oil.sleep(1)
  end
end
'



ADMINCMD="${OPENBUS_HOME}/bin/busadmin DEBUG"
if [ "$INITBUS" != "no" ]; then
  echo "Setting up core bus services"
  $ADMINCMD --login=admin --script=script.adm
fi
if [ "$INITBUS2" != "no" ]; then
  echo "Setting up second core bus services"
  $ADMINCMD --port=2090 --login=admin --script=script.adm
fi



CASES="\
simple \
delegation \
multiplexing \
sharedauth \
"
pid=
for case in $CASES; do
  echo "Executing interoperation test case '$case'"
  cd $case
  bash runall.sh
  cd ..
done
