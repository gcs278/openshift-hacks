#!/bin/bash

for i in $(find ~/src/haproxy.org/haproxy-2.3/ -type f -iname "haproxy-2.3.7-*"); do
  echo $i
  rm -rf haproxy*
  cp $i .
  version=$(./haproxy* --version 2>/dev/null | grep HA-Proxy | awk '{print $3}' | awk -F'-' '{print $1"-"$3"-"$2}')
  podman build -f Dockerfile.maxaccept64 -t quay.io/gspence/openshift-router:haproxy-$version .
  podman push quay.io/gspence/openshift-router:haproxy-$version
done
