#!/bin/bash

for i in $(find /tmp/pcap-tmp/ -iname "*pcap*"); do
#for i in $(find /tmp/pcaps-workers/$2 -iname "dumper*pcap"); do
#for i in $(find /tmp/pcaps-workers/$2 -iname "tcpdump*pcap*"); do
  echo $i;
  queries=$(tshark -r $i -n  -Y 'dns and not dns.retransmission and dns.flags.response == 0' -t ud | wc -l;)
  response=$(tshark -r $i -n  -Y 'dns and not dns.retransmission and dns.flags.response == 1' -t ud | wc -l;)
  echo "Queries: $queries Responses: $response Failures: $((queries-response)) Percent: $(bc -l <<<"(${queries}-${response})/${queries}") "
done
