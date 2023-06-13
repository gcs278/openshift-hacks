#!/bin/bash

podman run -p 8053:8053/tcp -p 8053:8053/udp quay.io/gspence/coredns-debug
