#!/bin/bash

if [[ ! -f namespaces/default/core/services.yaml ]]; then
  echo "ERROR: namespaces/default/core/services.yaml is not a file, are you in a must gather?"
  exit 1
fi
API_IP=$(grep -r "^\s*clusterIP:" namespaces/default/core/services.yaml | awk '{print $2}')
echo "Looking for API IP $API_IP errors..." 
for i in $(find ./namespaces -iname "current.log"); do
  out=$(grep -i "${API_IP}:443" $i | grep -ie error -ie "no route" -ie "fail")
  #out=$(grep -ie error -ie "no route" -ie "fail" $i)
  if [[ "$out" != "" ]]; then
    echo $i
    echo "$out"
    basedir=$(dirname $(dirname $(dirname $(dirname $i))))
    echo "Node Name:"
    grep -r "nodeName" ${basedir}/*.yaml | grep -v "fieldPath"
    echo 
  fi
done
