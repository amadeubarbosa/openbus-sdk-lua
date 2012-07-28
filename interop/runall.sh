#!/bin/bash

/bin/bash runtest.sh $1 simple server
/bin/bash runtest.sh $1 multiplexing server
/bin/bash runtest.sh $1 sharedauth server
/bin/bash runtest.sh $1 delegation messenger broadcaster forwarder
