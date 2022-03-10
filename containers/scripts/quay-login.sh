#!/bin/bash
set -e

ENGINE=$(command -v docker &> /dev/null && echo docker || echo podman)

if [[ "$ENGINE" == "docker" ]]; then
  echo "Login into quay.io:"
  $ENGINE login quay.io
  AUTH_FILE=~/.docker/config.json
else
  if ! $ENGINE login quay.io --get-login &> /dev/null; then
    echo "Login into quay.io:"
    $ENGINE login quay.io
  fi
  AUTH_FILE=${XDG_RUNTIME_DIR}/containers/auth.json
fi

# Make sure the build secret is created
oc create secret generic quay --dry-run=client --from-file=.dockerconfigjson=${AUTH_FILE} --type=kubernetes.io/dockerconfigjson -o yaml | oc apply -f -
