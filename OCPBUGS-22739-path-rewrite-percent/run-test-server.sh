#!/bin/bash

# build https://github.com/gcs278/haproxy-openshift/tree/test-server
./perf-test-hydra serve-backend -s -I --listen-port=8082 --traffic-type="http"
