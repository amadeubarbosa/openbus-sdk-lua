#!/bin/bash

mode=$1

function runner() {
  /bin/bash runtest.sh "$@" || exit $?
}

runner $mode protocol client server
runner $mode simple client server
runner $mode multiplexing client server
runner $mode sharedauth "sharing consuming"
runner $mode reloggedjoin client "server proxy"
runner $mode chaining client "server proxy"
runner $mode delegation client "messenger broadcaster forwarder"
