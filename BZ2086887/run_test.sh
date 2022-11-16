#!/bin/bash

if [[ ! -f "$1" ]]; then
  echo "ERROR: You need to pass a yaml file to reproduce"
  exit 1
fi

oc delete jobs.batch wget-job
oc delete jobs.batch curl-job

oc scale -n openshift-machine-api machineset gspence-2022-06-13-10-dhhxm-worker-c --replicas=1
while [[ $(oc get pods | wc -l) -gt 1 ]]; do
  echo "Waiting for pods to clean up"
  sleep 1
done

oc apply -f $1
