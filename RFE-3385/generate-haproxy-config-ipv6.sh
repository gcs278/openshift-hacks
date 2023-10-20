#!/bin/bash

rm haproxy.config.ipv6
cp haproxy.config.minimal haproxy.config.ipv6

for i in $(seq 1 $1); do
cat <<EOL >> haproxy.config.ipv6
backend test-${i}
  mode http
  balance random
  acl allowlist src -f /home/gspence/src/github.com/gcs278/openshift-hacks/RFE-3385/allowlists-ipv6/allowlist.txt${i}
  tcp-request content reject if !allowlist

  server web00 127.0.0.1:4040
  server web01 127.0.0.1:4040
EOL
done
