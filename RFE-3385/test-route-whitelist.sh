#!/bin/bash

oc apply -f - <<EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: echo-sleeper
  labels:
    app: echo-sleeper
spec:
  replicas: 1
  selector:
    matchLabels:
      app: echo-sleeper
  template:
    metadata:
      labels:
        app: echo-sleeper
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
        restartPolicy: Always
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
    app: echo-sleeper
  ports:
    - port: 8676
      name: echo-sleeper
      protocol: TCP
EOF

oc apply -f - <<EOF
apiVersion: route.openshift.io/v1
kind: Route
metadata:
  name: router-service1
  annotation:
    haproxy.router.openshift.io/ip_whitelist: 10.2.0.0/16
spec:
  to:
    kind: Service
    name: router-service1
EOF