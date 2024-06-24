#!/bin/bash
DIR=/tmp/gpt/$(date +%s)
mkdir -p $DIR
NS=$(oc get ns --no-headers | awk '{print $1}' | grep -i e2e-test-router);
for i in $(oc get pods -n $NS --no-headers | awk '{print $1}'); do
  echo "$i LOGS:" > ${DIR}/$i.log
  oc logs -n $NS $i --timestamps >> ${DIR}/$i.log
  echo "Created ${DIR}/$i.log"
done
