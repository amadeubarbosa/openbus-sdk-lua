#!/bin/bash

/bin/bash runtest.sh $1 protocol client server
/bin/bash runtest.sh $1 simple client server
/bin/bash runtest.sh $1 multiplexing client server
/bin/bash runtest.sh $1 sharedauth "sharing consuming"
/bin/bash runtest.sh $1 reloggedjoin client "server proxy"
/bin/bash runtest.sh $1 chaining client "server proxy"
/bin/bash runtest.sh $1 delegation client "messenger broadcaster forwarder"
