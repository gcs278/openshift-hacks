#!/bin/bash

if [[ ! -f namespaces/default/core/services.yaml ]]; then
  echo "ERROR: namespaces/default/core/services.yaml is not a file, are you in a must gather?"
  exit 1
fi

for i in $(grep -lri "nodeName: $1" ./namespaces --exclude=pods.yaml --exclude=endpoints.yaml --exclude=endpointslices.yaml); do
  basename=$(dirname $i)
  find $basename -iname "current.log"
done
