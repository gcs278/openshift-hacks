#!/bin/bash

podman build -f Dockerfile.binary -t quay.io/gspence/router:OCPBUGS12882-2.6.14-sigquit2
