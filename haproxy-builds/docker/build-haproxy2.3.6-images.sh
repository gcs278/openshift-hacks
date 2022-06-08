#!/bin/bash

for i in $(find ~/src/haproxy.org/haproxy-2.3/ -type f -iname "haproxy-2.3.6-*"); do
  echo $i
  rm -rf haproxy*
  cp $i .
  version=$(./haproxy* --version 2>/dev/null | grep HA-Proxy | awk '{print $3}')
  podman build -t quay.io/gspence/openshift-router:haproxy-$version .
  podman push quay.io/gspence/openshift-router:haproxy-$version
done
