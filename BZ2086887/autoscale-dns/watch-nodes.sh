#!/bin/bash

prev_nodes=$(oc get nodes --as system:admin --no-headers)
prev_nodes_count=$(oc get nodes --as system:admin --no-headers | wc -l)
while true; do
  nodes=$(oc get nodes --as system:admin --no-headers)
  nodes_count=$(oc get nodes --as system:admin --no-headers | wc -l)
  if [[ $nodes_count -gt $prev_nodes_count ]]; then
    echo "Added $((nodes_count - prev_nodes_count)) nodes:"
    comm -12 <(echo "$prev_nodes" | sort -h) <(echo "$nodes" | sort -h)
  elif [[ $nodes_count -lt $prev_nodes_count ]]; then
    echo "Removed $((prev_nodes_count - nodes_count)) nodes:"
    diff <(echo "$prev_nodes" | sort -h) <(echo "$nodes" | sort -h)
    echo -en "\007"
    echo -en "\007"
    echo -en "\007"
    echo -en "\007"
    echo -en "\007"
    echo -en "\007"
    echo -en "\007"
  fi
  sleep 1
  prev_nodes=$(oc get nodes --as system:admin --no-headers)
  prev_nodes_count=$(oc get nodes --as system:admin --no-headers | wc -l)
done
