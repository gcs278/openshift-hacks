#!/bin/bash

for i in $(oc get pods --no-headers | grep -i burst-test | awk '{print $1}'); do
  echo $i;
  logs=$(oc logs $i)
  requests=$(echo "$logs" | grep -i stats | tail -1 | awk -F' ' '{print $2}' | awk -F'=' '{print $2}')
  fails=$(echo "$logs" | grep -i stats | tail -1 | awk -F' ' '{print $4}' | awk -F'=' '{print $2}')
  total_requests=$((requests+total_requests))
  total_fails=$((fails+total_fails))
done
echo "Total Requests: $total_requests"
echo "Total Fails: $total_fails"
