#!/bin/bash

DIR=./certs/selfSigned
mkdir -p $DIR
cd $DIR

# Router rejects SHA1 self-signed cert, but HAProxy doesn't have any issues starting with self-signed SHA1
# certs in 4.16...so it's a false rejection.

# Self-Signed SHA1
openssl req -x509 -newkey rsa:2048 -keyout example-selfsigned.key -out example-selfsigned.pem -sha1 -days 3650 -nodes -subj "/C=US/ST=SC/L=Test/O=CompanyName/OU=CompanySectionName/CN=www.   example.com"

certSha1=$(cat example-selfsigned.pem)
certKeySha1=$(cat example-selfsigned.key)

oc apply -f - <<EOF
apiVersion: route.openshift.io/v1
kind: Route
metadata:
  name: router-service1
spec:
  port:
    targetPort: 8676
  to:
    kind: Service
    name: route-service1
  tls:
    termination: edge
    certificate: |-
$(echo "${certSha1}" | awk '{print "        "$0}')
    key: |-
$(echo "${certKeySha1}" | awk '{print "        "$0}')
EOF

echo "Route will be rejected, but since it's self signed, HAProxy still supports it"
