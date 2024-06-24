#!/bin/bash
if [[ "$1" == "" ]]; then
  echo "Error: You must provide a router name"
  exit 1
fi
router=$1
DIR=/tmp/router-logs/$(date +%s)
mkdir -p $DIR
NS=openshift-ingress
for i in $(oc get pods -n $NS --no-headers | grep "^router-${router}" | awk '{print $1}'); do
  echo "$i LOGS:" > ${DIR}/$i.log
  oc logs -n $NS $i --timestamps >> ${DIR}/$i.log
  echo "Created ${DIR}/$i.log"
done
