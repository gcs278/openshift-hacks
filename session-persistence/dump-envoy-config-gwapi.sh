#! /usr/bin/env bash

if [[ "$1" == "" ]]; then
  echo "ERROR: you must provide an namespace and pod"
  exit 1
fi

kill $(lsof -i :15000 | tail -1 | awk '{print $2}') &> /dev/null
oc port-forward --address 127.0.0.1 -n $1 pod/${2} 15000:15000 &

while true; do
  curl http://localhost:15000/config_dump && break
  sleep 1
done

kill $(jobs -p)
