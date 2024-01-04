#!/bin/bash

oc apply -f - <<EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: echo-sleeper-deployment
  labels:
    app: echo-sleeper-deployment
spec:
  replicas: 1
  selector:
    matchLabels:
      app: echo-sleeper-deployment
  template:
    metadata:
      labels:
        app: echo-sleeper-deployment
    spec:
      containers:
      - image: image-registry.openshift-image-registry.svc:5000/openshift/tools:latest
        name: echo-sleeper
        command:
        - /usr/bin/socat
        - TCP4-LISTEN:8676,reuseaddr,fork
        - EXEC:'/bin/bash -c \"sleep 1; printf \\\"HTTP/1.0 200 OK\r\n\r\n\\\"; sed -e \\\"/^\r/q\\\"\"'
        ports:
        - containerPort: 8676
          protocol: TCP
        dnsPolicy: ClusterFirst
        securityContext: {}
EOF

oc apply -f - <<EOF
apiVersion: v1
kind: Service
metadata:
  name: route-service1
  labels:
    app: echo-sleeper
spec:
  selector:
    app: echo-sleeper-deployment
  ports:
    - port: 8676
      name: echo-sleeper
      protocol: TCP
EOF
certSha1=$(cat cert-sha1.pem)

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
EOF
