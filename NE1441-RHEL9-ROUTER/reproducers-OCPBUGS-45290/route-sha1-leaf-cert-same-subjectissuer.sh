#!/bin/bash

DIR=./certs/intermediateCASameSubjectIssuerReproducer
mkdir -p $DIR
cd $DIR

echo "Going unmanaged and disabling the extendedvalidation plugin so you can see that this route is accepted"
oc scale --replicas 0 -n openshift-cluster-version deployments/cluster-version-operator
oc scale --replicas 0 -n openshift-ingress-operator deployments/ingress-operator
oc patch deployment/router-default -n openshift-ingress --patch='{"spec":{"template":{"spec":{"containers":[{"name":"router","env":[{"name":"EXTENDED_VALIDATION", "value":"false"}]}]}}}}'

# RootCA (HAProxy still supports SHA1 self-signed root CAs...so this is okay)
openssl req -x509 -sha1 -newkey rsa:2048 -days 3650 -keyout exampleca.key -out exampleca.crt -addext "keyUsage=cRLSign, digitalSignature, keyCertSign" -addext "extendedKeyUsage=serverAuth, clientAuth" -nodes -subj '/C=US/ST=SC/L=Default City/O=Default Company Ltd/OU=Test CA/CN=www.exampleca.com/emailAddress=example@example.com'

# Leaf, but it has the same Subject as the Root CA (Issuer==Subject), so HAProxy will work
openssl req -newkey rsa:2048 -nodes -keyout example.key -out example.csr -subj '/C=US/ST=SC/L=Default City/O=Default Company Ltd/OU=Test CA/CN=www.exampleca.com/emailAddress=example@example.com'
openssl x509 -req -days 3650 -sha1 -in example.csr -CA exampleca.crt -CAcreateserial -CAkey exampleca.key -extensions ext -extfile <(echo $'[ext]\nbasicConstraints = CA:FALSE\nsubjectKeyIdentifier = none\nauthorityKeyIdentifier = none\nextendedKeyUsage=serverAuth,clientAuth\nkeyUsage=nonRepudiation, digitalSignature, keyEncipherment') -out example.crt

caCertSha1=$(cat exampleca.crt)
certSha256=$(cat example.crt)
certKeySha256=$(cat example.key)

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
    caCertificate: |-
$(echo "${caCertSha1}" | awk '{print "        "$0}')
    certificate: |-
$(echo "${certSha256}" | awk '{print "        "$0}')
    key: |-
$(echo "${certKeySha256}" | awk '{print "        "$0}')
EOF

echo "Route contains leaf SHA1 cert that has the same subject & issuer, but won't cause HAProxy to fail to reload/start"
