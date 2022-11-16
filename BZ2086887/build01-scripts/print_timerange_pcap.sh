#!/bin/bash

#for i in $(find /tmp/pcaps-workers -maxdepth 1 -iname "*pcap"); do
# start=$(tshark -r $i -t ud -Y '' 2> /dev/null | head -1 | awk '{print $3}';)
# finish=$(tshark -r $i -t ud -Y '' 2> /dev/null | tail -1 | awk '{print $3}';)
# echo "File: $(basename $i): $start : $finish"
#done

export TZ=utc
for i in $(find /tmp/pcaps-workers -maxdepth 1 -iname "dumper*" -type d); do
  if ls $i/tcpdump* &> /dev/null; then
    echo $(basename $i)
    ls -ltc $i/tcpdump* | head -1
    ls -ltc $i/tcpdump* | tail -1
  fi
done
