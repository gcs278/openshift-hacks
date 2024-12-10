#!/bin/bash

# This reproducer is a bit different, HAProxy will start, but SSL verification will fail with SHA1 intermediate Dest CA certs
# So curling the route fails in 4.16+ but it worked in 4.15 (regression)

DIR=./certs/destinationCAReproducer
mkdir -p $DIR
cd $DIR

# RootCA (HAProxy still supports SHA1 self-signed root CAs...so this is okay)
openssl req -x509 -sha1 -newkey rsa:2048 -days 3650 -keyout exampleca.key -out exampleca.crt -addext "keyUsage=cRLSign, digitalSignature, keyCertSign" -addext "extendedKeyUsage=serverAuth, clientAuth" -nodes -subj '/C=US/ST=SC/L=Default City/O=Default Company Ltd/OU=Test CA/CN=www.exampleca.com/emailAddress=example@example.com'

# IntermediateCA (SHA1 will cause SSL failure)
openssl req -newkey rsa:1024 -nodes -keyout example-intermediate.key -out example-intermediate.csr -subj '/CN=www.exampleintermediate.com/ST=SC/C=US/emailAddress=example@example.com/O=Example/OU=Example'
openssl req -x509 -sha1 -days 3650 -in example-intermediate.csr -CA exampleca.crt -CAkey exampleca.key -out example-intermediate.crt -addext "keyUsage=cRLSign, digitalSignature, keyCertSign" -addext "extendedKeyUsage=serverAuth, clientAuth" -nodes -subj '/C=US/ST=SC/L=Default City/O=Default Company Ltd/OU=Test CA/CN=www.exampleintermediate.com/emailAddress=example@example.com'

# Leaf
openssl req -newkey rsa:2048 -nodes -keyout example.key -out example.csr -subj '/CN=www.example.com/ST=SC/C=US/emailAddress=example@example.com/O=Example/OU=Example'
openssl x509 -req -days 3650 -sha256 -in example.csr -CA example-intermediate.crt -CAcreateserial -CAkey example-intermediate.key -extensions ext -extfile <(echo $'[ext]\nbasicConstraints = CA:FALSE\nsubjectKeyIdentifier = none\nauthorityKeyIdentifier = none\nextendedKeyUsage=serverAuth,clientAuth\nkeyUsage=nonRepudiation, digitalSignature, keyEncipherment') -out example.crt

domain=$(oc get ingresses.config/cluster -o jsonpath={.spec.domain})
openssl req -newkey rsa:2048 -nodes -keyout nginx-ssl.key -out nginx-ssl.csr -subj '/CN=*.'${domain}'/ST=SC/C=US/emailAddress=example@example.com/O=Example/OU=Example'
openssl x509 -req -days 3650 -sha256 -in nginx-ssl.csr -CA example-intermediate.crt -CAcreateserial -CAkey example-intermediate.key -extensions ext -extfile <(echo $'[ext]\nbasicConstraints = CA:FALSE\nsubjectKeyIdentifier = none\nauthorityKeyIdentifier = none\nextendedKeyUsage=serverAuth,clientAuth\nkeyUsage=nonRepudiation, digitalSignature, keyEncipherment') -out nginx-ssl.crt

oc delete secret server-certs
oc create secret tls server-certs --key=nginx-ssl.key --cert=nginx-ssl.crt

oc apply -f - <<EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: nginx-ssl-deployment
  labels:
    app: nginx-ssl-deployment
spec:
  replicas: 1
  selector:
    matchLabels:
      app: nginx-ssl-deployment
  template:
    metadata:
      labels:
        app: nginx-ssl-deployment
    spec:
      containers:
      - image: quay.io/gspence/nginx-ssl
        name: nginx-ssl
        ports:
        - containerPort: 8443
          protocol: TCP
        dnsPolicy: ClusterFirst
        securityContext: {}
        ports:
        - containerPort: 8443
        volumeMounts:
        - name: cert
          mountPath: /etc/nginx/certs
      volumes:
      - name: cert
        secret:
          secretName: server-certs
          items:
          - key: tls.crt
            path: server.crt
          - key: tls.key
            path: server.key

EOF

oc rollout restart deployment nginx-ssl-deployment
$(echo "${interCertSha1}" | awk '{print "        "$0}')

oc apply -f - <<EOF
apiVersion: v1
kind: Service
metadata:
  name: route-service1
  labels:
    app: nginx-ssl
spec:
  selector:
    app: nginx-ssl-deployment
  ports:
    - port: 8443
      name: nginx-ssl
      protocol: TCP
EOF
caCertSha1=$(cat exampleca.crt)
intermediateCertSha1=$(cat example-intermediate.crt)

oc apply -f - <<EOF
apiVersion: route.openshift.io/v1
kind: Route
metadata:
  name: router-service1
spec:
  port:
    targetPort: 8443
  to:
    kind: Service
    name: route-service1
  tls:
    termination: reencrypt
    destinationCACertificate: |-
$(echo "${caCertSha1}" | awk '{print "        "$0}')
$(echo "${intermediateCertSha1}" | awk '{print "        "$0}')
EOF

echo "Curl-ing route will FAIL with SSL error due to unsupported SHA1 destination CA cert (this used to work on 4.15)"
