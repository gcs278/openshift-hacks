#!/bin/bash

set -e
if [[ "$1" == "" ]];then
  echo "You must provided a query"
  exit 1
fi

workers="$(oc get nodes | grep worker | awk '{print $1}')"

for i in $(oc get pods -n openshift-dns | grep dumper | awk '{print $1}'); do
  echo $i
  node=$(oc get pods -n openshift-dns $i -o wide | awk '{print $7}')
  if echo "$workers" | grep -qi "$node"; then
    echo "Found that $i is on a worker node $node"
    oc cp -n openshift-dns ./find_query_pcaps_embedded.sh ${i}:/tmp/
    set +e
    oc exec -n openshift-dns $i /tmp/find_query_pcaps_embedded.sh $1
    if [[ $? -eq 0 ]]; then
      echo "FOUND!"
      exit 0
    fi
    set -e
  fi
done
