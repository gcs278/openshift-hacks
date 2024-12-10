#!/bin/bash

# NOTE: This is a reproducer for how the Ingress Operator in 4.15 should block upgrades to 4.16
# if an Intermediate SHA1 Cert is provided. We don't reject any default certs for the IngressController
# so it's going to fail regardless in 4.16+. But 4.16 *should* block upgrades for this scenario.

DIR=./certs/intermediateCADefaultCertReproducer
mkdir -p $DIR
cd $DIR

# RootCA (HAProxy still supports SHA1 self-signed root CAs...so this is okay)
openssl req -x509 -sha1 -newkey rsa:2048 -days 3650 -keyout exampleca.key -out exampleca.crt -addext "keyUsage=cRLSign, digitalSignature, keyCertSign" -addext "extendedKeyUsage=serverAuth,  clientAuth" -nodes -subj '/C=US/ST=SC/L=Default City/O=Default Company Ltd/OU=Test CA/CN=www.exampleca.com/emailAddress=example@example.com'

# IntermediateCA (SHA1 will cause HAProxy to fail)
openssl req -newkey rsa:1024 -nodes -keyout example-intermediate.key -out example-intermediate.csr -subj '/CN=www.exampleintermediate.com/ST=SC/C=US/emailAddress=example@example.com/O=Example/OU=Example'
openssl req -x509 -sha1 -days 3650 -in example-intermediate.csr -CA exampleca.crt -CAkey exampleca.key -out example-intermediate.crt -addext "keyUsage=cRLSign, digitalSignature,             keyCertSign" -addext "extendedKeyUsage=serverAuth, clientAuth" -nodes -subj '/C=US/ST=SC/L=Default City/O=Default Company Ltd/OU=Test CA/CN=www.exampleintermediate.com/emailAddress=example@ example.com'

# Leaf
openssl req -newkey rsa:2048 -nodes -keyout example.key -out example.csr -subj '/CN=www.example.com/ST=SC/C=US/emailAddress=example@example.com/O=Example/OU=Example'
openssl x509 -req -days 3650 -sha256 -in example.csr -CA example-intermediate.crt -CAcreateserial -CAkey example-intermediate.key -extensions ext -extfile <(echo $'[ext]\nbasicConstraints = CA:FALSE\nsubjectKeyIdentifier = none\nauthorityKeyIdentifier = none\nextendedKeyUsage=serverAuth,clientAuth\nkeyUsage=nonRepudiation, digitalSignature, keyEncipherment') -out example.crt

# Bundle the certs up together
cat example.crt example-intermediate.crt exampleca.crt > example-combo.crt
oc delete secret -n openshift-ingress router-cert
oc create secret -n openshift-ingress tls router-cert --key=example.key --cert=example-combo.crt

domain=$(oc get dnses cluster -o jsonpath={.spec.baseDomain})
export test_domain="demo.${domain}"

oc apply -f - <<EOF
apiVersion: operator.openshift.io/v1
kind: IngressController
metadata:
  name: demo
  namespace: openshift-ingress-operator
spec:
  domain: $test_domain
  replicas: 1
  endpointPublishingStrategy:
    type: LoadBalancerService
    loadBalancer:
      DNSManagementPolicy: Managed
      scope: External
  nodePlacement:
    nodeSelector:
      matchLabels:
        node-role.kubernetes.io/worker: ""
  defaultCertificate:
    name: router-cert
EOF

echo "Router pods for IngressController will fail to start...that's expected, but we should block upgrades from 4.15 to 4.16 with this scenario"
