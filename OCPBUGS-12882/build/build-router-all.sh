#!/bin/bash

set -e

for i in $(find ~/src/haproxy.org/haproxy-2.7/ -iname "haproxy-2.7.*" -maxdepth 1 -mindepth 1); do
  echo $i;
  rm -f haproxy-2.7*
  cp $i .
  podman build -f Dockerfile.binary -t quay.io/gspence/router:OCPBUGS12882-$(basename $i)
  podman push quay.io/gspence/router:OCPBUGS12882-$(basename $i)
done
