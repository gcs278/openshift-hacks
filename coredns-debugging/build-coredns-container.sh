#!/bin/bash

cp ~/src/github.com/coredns/coredns/coredns .
podman build -f Dockerfile -t quay.io/gspence/coredns-debug .
