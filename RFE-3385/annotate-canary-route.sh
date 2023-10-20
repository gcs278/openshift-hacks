#!/bin/bash

whitelist=""
for i in {1..1000}; do
  first=10
  second=1
  third=1
  if [[ $i -lt 256 ]]; then
    forth=$i
  elif [[ $i -ge 256 ]]; then
    third=2
    forth=$((i % 256))
  elif [[ $i -ge 512 ]]; then
    third=3
    forth=$((i % 512))
  elif [[ $i -ge 768 ]]; then
    third=4
    forth=$((i % 768))
  elif [[ $i -ge 1024 ]]; then
    third=5
    forth=$((i % 1024))
  fi
  whitelist="${whitelist} ${first}.${second}.${third}.${forth}/32"
done

whitelist=$(echo "$whitelist" | xargs)

oc annotate --overwrite route -n openshift-ingress-canary  canary haproxy.router.openshift.io/ip_whitelist="$whitelist"
