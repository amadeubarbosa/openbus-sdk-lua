#!/bin/bash

/bin/bash rundemo.sh $1 hello
/bin/bash rundemo.sh $1 greetings
/bin/bash rundemo.sh $1 dedicatedclock
/bin/bash rundemo.sh $1 independentclock
/bin/bash rundemo.sh $1 callchain
/bin/bash rundemo.sh $1 multiplexing

/bin/bash rundemo.sh $1 assistant/hello
/bin/bash rundemo.sh $1 assistant/greetings
/bin/bash rundemo.sh $1 assistant/dedicatedclock
/bin/bash rundemo.sh $1 assistant/independentclock
/bin/bash rundemo.sh $1 assistant/callchain
