#!/bin/bash

mkdir /tmp/pcaps/
rm -f /tmp/pcaps/*


for i in $(oc get pods -n openshift-dns | grep dumper | awk '{print $1}'); do
  echo $i
  oc rsync --progress -n openshift-dns ${i}:/tmp/ /tmp/pcaps/
  if [[ $? -ne 0 ]]; then
    echo "failed to get pcap from $i"
    continue
  fi
  for j in /tmp/pcaps/tcpdump.pcap*; do
    ./pcapfix-1.1.7/pcapfix ${j} -k --outfile ${j}.fixed.pcap
    rm -f $j
  done
  mergecap /tmp/pcaps/*.fixed.pcap -w /tmp/pcaps/$i.pcap
  rm -f /tmp/pcaps/*.fixed.pcap
done
