#!/bin/bash

values=$(cat <<EOF
External DYNAMIC @CoreDNS
External DYNAMIC @8.8.8.8
External DYNAMIC @10.0.0.2
Internal DYNAMIC @CoreDNS
Internal LB_ADDRESS @CoreDNS
External LB_ADDRESS @8.8.8.8
External STATIC @8.8.8.8
External LB_ADDRESS @10.0.0.2
External LB_ADDRESS @CoreDNS
Internal STATIC @CoreDNS
External STATIC @10.0.0.2
External STATIC @CoreDNS
EOF
)
while IFS= read -r value; do
  echo -ne "$value\t"
  cat $1 | grep "\[$value\] query" | awk '{print $7}' | awk -F'=' '{print $2}' | awk '
  {
    if ($0 ~ /m/) {
        split($0, a, "m")
        split(a[2], b, "s")
        total_seconds = a[1] * 60 + b[1]
    } else if ($0 ~ /s/) {
        if ($0 ~ /ms/) {
            split($0, a, "ms")
            total_seconds = a[1] / 1000
        } else {
            split($0, a, "s")
            total_seconds = a[1]
        }
    }
    print total_seconds
}'| awk '{print $1 / 60}' | awk '{printf "%s\t", $0}'
  echo
done <<< "$values"
