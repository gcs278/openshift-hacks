#!/bin/bash

DIR=/tmp
openssl req -x509 -sha256 -newkey rsa:2048 -days 3650 -keyout ${DIR}/exampleca.key -out ${DIR}/exampleca.crt -addext "keyUsage=cRLSign, digitalSignature, keyCertSign" -addext "extendedKeyUsage=serverAuth,  clientAuth" -nodes -subj '/C=US/ST=SC/L=Default City/O=Default Company Ltd/OU=Test CA/CN=www.exampleca.com/emailAddress=example@example.com'
openssl req -newkey rsa:2048 -nodes -keyout ${DIR}/example.key -out ${DIR}/example.csr -subj '/CN=www.example.com/ST=SC/C=US/emailAddress=example@example.com/O=Example/OU=Example'
openssl x509 -req -days 3650 -sha256 -in ${DIR}/example.csr -CA ${DIR}/exampleca.crt -CAcreateserial -CAkey ${DIR}/exampleca.key -extensions ext -extfile <(echo $'[ext]\nbasicConstraints = CA:FALSE\nsubjectKeyIdentifier = none\nauthorityKeyIdentifier = none\nextendedKeyUsage=serverAuth,clientAuth\nkeyUsage=nonRepudiation, digitalSignature, keyEncipherment') -out ${DIR}/example.crt

oc delete secret nginx-ssl-secret
openssl req -newkey rsa:2048 -nodes -keyout ${DIR}/nginx.key -out ${DIR}/nginx.csr -subj '/CN=route-ssl.default.svc/ST=SC/C=US/emailAddress=example@example.com/O=Example/OU=Example'
openssl x509 -req -days 3650 -sha256 -in ${DIR}/nginx.csr -CA ${DIR}/exampleca.crt -CAcreateserial -CAkey ${DIR}/exampleca.key -extensions ext -extfile <(echo $'[ext]\nbasicConstraints = CA:FALSE\nsubjectKeyIdentifier = none\nauthorityKeyIdentifier = none\nextendedKeyUsage=serverAuth,clientAuth\nkeyUsage=nonRepudiation, digitalSignature, keyEncipherment') -out ${DIR}/nginx.crt
oc create secret tls nginx-ssl-secret --cert=/tmp/nginx.crt --key=/tmp/nginx.key


#oc create configmap nginx-cas -n openshift-config --from-file=example.com=${DIR}/exampleca.key 
#oc patch image.config.openshift.io/cluster --patch '{"spec":{"additionalTrustedCA":{"name":"nginx-cas"}}}' --type=merge

oc apply -f - <<EOF
apiVersion: v1
kind: ConfigMap
metadata:
  name: nginx-config
data:
  default.conf: |
    server {
        listen 443 ssl;
        server_name localhost;

        ssl_certificate /etc/nginx/ssl/tls.crt;
        ssl_certificate_key /etc/nginx/ssl/tls.key;

        location / {
            root /usr/share/nginx/html;
            index index.html index.htm;
        }
    }
EOF


oc apply -f - <<EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: echo-server
  labels:
    app: echo-server
spec:
  replicas: 1
  selector:
    matchLabels:
      app: echo-server
  template:
    metadata:
      labels:
        app: echo-server
    spec:
      containers:
        - name: echo-server
          image: quay.io/gspence/nginx-ssl
          ports:
            - containerPort: 443
          volumeMounts:
            - name: ssl-certs
              mountPath: /etc/nginx/ssl
              readOnly: true
            - name: nginx-config
              mountPath: /etc/nginx/conf.d/default.conf
              subPath: default.conf
              readOnly: true
          #command: ["/bin/sh", "-c", "sleep 900"]
          #command: ["/bin/sh", "-c", "envsubst '$$NGINX_HOST' < /etc/nginx/nginx.conf.template > /etc/nginx/nginx.conf && exec nginx -g 'daemon off;'"]
      volumes:
        - name: ssl-certs
          secret:
            secretName: route-ssl
        - name: nginx-config
          configMap:
            name: nginx-config  
EOF

oc apply -f - <<EOF
apiVersion: v1
kind: Service
metadata:
  name: route-ssl
  labels:
    app: echo-server
  annotations:
    service.beta.openshift.io/serving-cert-secret-name: route-ssl
spec:
  selector:
    app: echo-server
  ports:
    - port: 443
      name: echo-server
      protocol: TCP
EOF

certSha256=$(cat ${DIR}/example.crt)
certKeySha256=$(cat ${DIR}/example.key)
caCertSha256=$(cat ${DIR}/exampleca.crt)

oc apply -f - <<EOF
apiVersion: route.openshift.io/v1
kind: Route
metadata:
  name: route-ssl
spec:
  port:
    targetPort: 443
  to:
    kind: Service
    name: route-ssl
  tls:
    termination: reencrypt
    certificate: |-
$(echo "${certSha256}" | awk '{print "        "$0}')
    key: |-
$(echo "${certKeySha256}" | awk '{print "        "$0}')
EOF

#    destinationCACertificate: |-
#$(echo "${caCertSha256}" | awk '{print "        "$0}')

oc rollout restart deployment echo-server
