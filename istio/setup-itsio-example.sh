#!/bin/bash

HELPER="./helper-scripts"

# Install Istio and Gateway API
${HELPER}/install-istio-gwapi.sh

# Clear certs for new installation
rm -rf /tmp/istio-certs

# Configure nginx examples
${HELPER}/create-nginx-examples.sh

# Convert the console route to istio ingress
${HELPER}/convert-console-route.sh
