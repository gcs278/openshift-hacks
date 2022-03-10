#!/bin/bash

set -euo pipefail

if [[ "$1" == "" ]]; then
  echo "ERROR: You must provide an image name"
  exit 1
fi

IMAGE_NAME="$1"

if oc get builds -l buildconfig=${IMAGE_NAME} | grep -q New; then
  echo "ERROR: Another build is running and make be stuck." 
  echo "       oc get builds -l buildconfig=${IMAGE_NAME}" 
  oc get builds -l buildconfig=${IMAGE_NAME}
  exit 1
fi

oc start-build ${IMAGE_NAME} --follow --wait
