#!/bin/bash

podman build -f Dockerfile -t quay.io/gspence/dns-propagate .
podman push quay.io/gspence/dns-propagate
