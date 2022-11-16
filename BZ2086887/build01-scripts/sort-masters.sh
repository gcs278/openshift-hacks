#!/bin/bash

mkdir /tmp/pcaps/masters -p
for dns_pod in $(oc get pod -n openshift-dns --no-headers | grep dns-default | awk '{print $1}'); do
  hostIp=$(oc get pod -n openshift-dns $dns_pod -o yaml | grep -i hostIp | awk '{print $2}')
  echo $hostIp
  for i in /tmp/pcaps/*.pcap; do
    file=$(basename $i)
    pod=${file%.pcap}
    echo $pod

    if oc get pod -n openshift-dns $pod -o yaml | grep -qi $hostIp; then
      echo "Master: $dns_pod = $pod"
      mv $i /tmp/pcaps/masters/
    fi
    
  done
done
