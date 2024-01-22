#!/bin/bash

set -u
set -e

pkill haproxy-2.6.13 || true

table="Address_Type Backends Cidrs TotalCIDRFileSize_MB VMSize_MB VMPeak_MB HaproxyStartupTime_S\n"
lines="------------ -------- ----- -------------------- --------- --------- --------------------\n"
table="${table}${lines}"
for mode in "ipv4"; do
#for mode in "ipv4" "ipv6"; do
  for num_backends in 1000; do
  #for num_backends in 0 1 500 1000 2000 3000; do
    for num_cidrs in 30000; do
    #for num_cidrs in 0 1 1000 2000 4000 10000; do
      if [[ "$num_cidrs" -eq 0 ]] && [[ "$num_backends" -ne 0 ]]; then
        continue
      fi
      mkdir -p allowlists-${mode}
      rm -f allowlists-${mode}/*
      cd allowlists-${mode}

      echo "Generating allowlists with $num_cidrs cidrs for $num_backends backends"
      ../generate-allowlist-${mode}.sh $num_cidrs
      if [[ "$num_backends" -gt 0 ]]; then
        for i in $(seq 1 $num_backends); do
          cp allowlist.txt allowlist.txt${i}
        done
      fi
      rm allowlist.txt

      cd ..
      ./generate-haproxy-config-${mode}.sh $num_backends
      START=$(date +%s.%N)
      #perf record /home/gspence/src/haproxy.org/haproxy-2.6/haproxy-2.6.13 -f haproxy.config.${mode} -D
      /home/gspence/src/haproxy.org/haproxy-2.6/haproxy-2.6.13 -f haproxy.config.${mode} -D
      END=$(date +%s.%N)
      DIFF=$(printf "%.2f" $(echo "$END - $START" | bc))
      PID=$(pgrep haproxy-2.6.13)
      sleep 5
      vmPeakKB=$(cat /proc/${PID}/status | grep ^VmPeak  | awk '{print $2}')
      vmSizeKB=$(cat /proc/${PID}/status | grep ^VmSize  | awk '{print $2}')
      vmPeakMB=$((vmPeakKB/1024))
      vmSizeMB=$((vmSizeKB/1024))
      pkill haproxy-2.6.13
      totalFileSize=$(du -m allowlists-${mode} | awk '{print $1}')

      table="${table}${mode} ${num_backends} ${num_cidrs} ${totalFileSize} ${vmSizeMB} ${vmPeakMB} ${DIFF}\n"
      echo -e "$table"
      if [[ "$num_backends" -eq 0 ]]; then
        break
      fi
    done
  done
done
echo -e "$table" | column -t > allowlist-results.txt
