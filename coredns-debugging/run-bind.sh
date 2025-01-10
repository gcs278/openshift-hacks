#!/bin/bash

podman run --network=host docker.io/ubuntu/bind9 -p 6053
