#!/bin/bash
trap 'kill $(jobs -p)' EXIT
SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
IMG="docker.io/envoyproxy/envoy"
VER="v1.24-latest"

echo "Starting backends..."
./perf-test-hydra serve-backend --traffic-type=http -s -I --listen-port=2000 &
./perf-test-hydra serve-backend --traffic-type=http -s -I --listen-port=2001 &

echo "Starting Envoy..."

podman rm envoy &>/dev/null
podman run --name=envoy --network=host -it -v ${SCRIPT_DIR}/envoy/envoy-static-example-cookies.yaml:/envoy-static.yaml:z  ${IMG}:${VER} -c /envoy-static.yaml
