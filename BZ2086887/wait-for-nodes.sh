#!/bin/bash

while true; do
 if [[ $(oc get nodes | wc -l) -gt 6 ]]; then
     notify-send "NEW NODES"
     echo -en "\007"
     break 1
 fi
 sleep 1
done
