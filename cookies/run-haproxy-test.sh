#!/bin/bash

trap 'kill $(jobs -p)' EXIT

HAPROXY=~/src/haproxy.org/haproxy-2.6/haproxy-2.6.13

echo "Starting backends..."
# Build github.com/gcs278/haproxy-openshift/perf@test-server
./perf-test-hydra serve-backend --traffic-type=http -s -I --listen-port=2000 &
./perf-test-hydra serve-backend --traffic-type=http -s -I --listen-port=2001 &

echo "Starting HaProxy..."
$HAPROXY -f haproxy/haproxy.config -db -V
