#!/bin/bash

for i in $(find /tmp/pcaps/masters -iname "*pcap"); do
  echo $i;
  tshark -r $i -n  -Y 'dns.qry.name contains "'$1'"' -t ud;
done
