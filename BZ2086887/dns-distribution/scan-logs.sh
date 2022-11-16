#!/bin/bash

for i in $(oc get pods --no-headers | grep -i dns-distribution | awk '{print $1}'); do
  echo $i;
  logs=$(oc logs $i tcpdump --timestamps)
  echo "$logs"
done
