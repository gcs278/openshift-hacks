#!/bin/bash
set -e

setcookie=$(curl -s localhost:8080 -H "host: perf-test-hydra-http-0" -I | grep -i "set-cookie")
echo $setcookie
cookie=$(echo "$setcookie" | awk '{print $2}' | awk -F';' '{print $1}')
echo "$cookie" 

while true; do
  curl -s localhost:8080 --cookie $cookie -H "host: perf-test-hydra-http-0"
  sleep 1
done
