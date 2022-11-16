#!/bin/bash

for i in $(oc get pods --no-headers | grep -i burst-test | awk '{print $1}'); do
  echo $i;
  logs=$(oc logs $i --timestamps)
  #echo "$logs" | grep -i starting
  #echo "$logs" | grep FAIL -A 4
  echo "$logs" | grep stats -i
done
