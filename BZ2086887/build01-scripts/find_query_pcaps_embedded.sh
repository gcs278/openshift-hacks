#!/bin/bash

rpm -qa | grep -q wireshark-cli || dnf -y install https://rpmfind.net/linux/centos/8-stream/AppStream/x86_64/os/Packages/wireshark-cli-2.6.2-12.el8.x86_64.rpm http://rpmfind.net/linux/centos/8-stream/BaseOS/x86_64/os/Packages/c-ares-1.13.0-5.el8.x86_64.rpm https://rpmfind.net/linux/centos/8-stream/AppStream/x86_64/os/Packages/libsmi-0.4.8-23.el8.x86_64.rpm

for i in $(find /tmp/ -iname "tcpdump*pcap*"); do
  echo "Searching $i";
  OUT=$(tshark -r $i -n  -Y 'dns.qry.name contains "'$1'"' -t ud;)
  if [[ "$OUT" != "" ]]; then
    echo "HIT!"
    echo "$OUT"
    exit 0
  fi
done

exit 1
