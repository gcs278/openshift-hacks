#!/bin/bash

workers="$(oc get nodes | grep worker | awk '{print $1}')"

for i in $(oc get pods -n openshift-dns | grep dumper | awk '{print $1}'); do
  echo $i
  node=$(oc get pods -n openshift-dns $i -o wide | awk '{print $7}')
  if echo "$workers" | grep -qi "$node"; then
    echo "Found that $i is on a worker node $node"
    oc exec -n openshift-dns $i -- bash -c 'stat -c '%y' /tmp/tcpdump.pcap* | sort -h | head -1 ; stat -c '%y' /tmp/tcpdump.pcap* | sort -h | tail -1 '
  fi
done
