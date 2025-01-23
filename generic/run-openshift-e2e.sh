#!/usr/bin/env bash

i=0

#t=TestRouteNotUpgradeableWithSha1
t=TestAWSLBSubnets
#t=TestUnmanagedAWSLBSubnets
mkdir -p /tmp/e2e-output

while :; do
    OUT=/tmp/e2e-output/${t}-${i}.log
    echo "logging to $OUT"
    echo "running..."
    make TEST=${t} test-e2e > $OUT
    if [ $? -eq 0 ]; then
	espeak-ng $i
    else
	espeak-ng $i BOOM
        exit 1
    fi
    i=$((i + 1))
    echo "************************************************** RAN $i TIMES"
done
