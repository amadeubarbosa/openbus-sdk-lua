#!/bin/bash

/bin/bash runtest.sh $1 protocol server
/bin/bash runtest.sh $1 simple server
/bin/bash runtest.sh $1 multiplexing server
/bin/bash runtest.sh $1 sharedauth server
/bin/bash runtest.sh $1 reloggedjoin server proxy
/bin/bash runtest.sh $1 chaining server proxy
/bin/bash runtest.sh $1 delegation messenger broadcaster forwarder
