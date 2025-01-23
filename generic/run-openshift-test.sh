#!/usr/bin/env bash

# % ./openshift-tests run --dry-run  openshift/conformance   | grep http2

#t="[sig-network-edge][Conformance][Area:Networking][Feature:Router][apigroup:route.openshift.io][apigroup:config.openshift.io] The HAProxy router should pass the http2 tests [apigroup:image.openshift.io][apigroup:operator.openshift.io] [Suite:openshift/conformance/parallel/minimal]"

#t="[sig-network-edge][Conformance][Area:Networking][Feature:Router] The HAProxy router should pass the gRPC interoperability tests [apigroup:route.openshift.io][apigroup:operator.openshift.io] [Suite:openshift/conformance/parallel/minimal]"

#t="[sig-network-edge][Conformance][Area:Networking][Feature:Router][apigroup:route.openshift.io] The HAProxy router should pass the h2spec conformance tests [apigroup:authorization.openshift.io][apigroup:user.openshift.io][apigroup:security.openshift.io][apigroup:operator.openshift.io] [Suite:openshift/conformance/parallel/minimal]"

#t="[sig-network][Feature:Router][apigroup:route.openshift.io] The HAProxy router converges when multiple routers are writing conflicting status [Suite:openshift/conformance/parallel]"
#t="[sig-network][Feature:Router][apigroup:route.openshift.io] The HAProxy router converges when multiple routers are writing status [Suite:openshift/conformance/parallel]"


t="[sig-network][Feature:Router][apigroup:route.openshift.io] The HAProxy router converges when multiple routers are writing conflicting upgrade validation status [Suite:openshift/conformance/parallel]"

i=0
mkdir -p /tmp/e2e-output
while :; do
    OUT=/tmp/e2e-output/origin-${i}.log
    echo "logging to $OUT"
    echo "running..."
    ./openshift-tests run-test "$t" > $OUT
    if [ $? -eq 0 ]; then
	espeak-ng $i
    else
	espeak-ng $i BOOM
	echo "FAILED!"
        exit 1
    fi
    i=$((i + 1))
    echo "************************************************** RAN $i TIMES"
done
