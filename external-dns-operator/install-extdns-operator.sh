#!/bin/bash

set -e

export CONTAINER_ENGINE=podman
export REGISTRY=quay.io
export REPOSITORY=gspence
export VERSION=1.0.0

${CONTAINER_ENGINE} login ${REGISTRY} -u ${REPOSITORY}

export IMG=${REGISTRY}/${REPOSITORY}/external-dns-operator:${VERSION}
make image-build image-push

make deploy

hack/generate-certs.sh --service webhook-service --webhook validating-webhook-configuration \
--secret webhook-server-cert --namespace external-dns-operator
