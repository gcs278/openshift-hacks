#!/bin/bash

for i in $(find /tmp/pcaps-workers/$2 -iname "tcpdump*pcap*"); do
  echo $i;
  tshark -r $i -n  -Y 'dns.qry.name contains "'$1'"' -t ud;
done
