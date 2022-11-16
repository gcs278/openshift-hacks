#!/bin/bash

# Fix all pcaps
echo "Fixing all pcaps"
for i in $(find . -iname "*pcap*"); do
  ~/src/github.com/gcs278/openshift-hacks/BZ2086887/pcapfix-1.1.7/pcapfix $i -k -o ${i}.fixed
  mv ${i}.fixed ${i}
done

for i in $(find . -iname "dumper-*" -type d); do
  mergecap -a ${i}/tcpdump.pcap* -w ${i}/combined.pcap
  rm -f ${i}/tcpdump.pcap*
done

for i in $(find . -iname "*pcap*"); do
  reordercap $i $i.ordered
  mv $i.ordered $i
done
