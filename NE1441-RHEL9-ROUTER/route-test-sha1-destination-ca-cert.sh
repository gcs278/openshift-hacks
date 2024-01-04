#!/bin/bash


openssl req -newkey rsa:2048 -nodes -keyout nginx-ssl.key -out nginx-ssl.csr -subj '/CN=www.example.com/ST=SC/C=US/emailAddress=example@example.com/O=Example/OU=Example'
openssl x509 -req -days 3650 -sha256 -in nginx-ssl.csr -CA exampleca.crt -CAcreateserial -CAkey exampleca.key -extensions ext -extfile <(echo $'[ext]\nbasicConstraints = CA:FALSE\nsubjectKeyIdentifier = none\nauthorityKeyIdentifier = none\nextendedKeyUsage=serverAuth,clientAuth\nkeyUsage=nonRepudiation, digitalSignature, keyEncipherment') -out nginx-ssl.crt

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
caCertSha256Wrong=$(cat sha256/exampleca.crt)
caKeySha1=$(cat exampleca.key)
certSha1=$(cat example.crt)
certKeySha1=$(cat example.key)

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
EOF
