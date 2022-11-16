#!/bin/bash

for i in $(find /tmp/pcaps-workers/$2 -iname "tcpdump*pcap*"); do
  echo $i;
  tshark -r $i -n  -Y 'dns and not dns.retransmission and (dns.flags.response == 0) && ! dns.response_in' -t ud;
done
