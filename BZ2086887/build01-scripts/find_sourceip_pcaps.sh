#!/bin/bash

for i in $(find /tmp/pcaps-workers/ -iname "*pcap"); do
  echo $i;
  tshark -r $i -n  -Y 'ip.addr == '$1'' -t ud;
done
