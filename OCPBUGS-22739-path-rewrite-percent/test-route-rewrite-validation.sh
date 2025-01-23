#!/bin/bash
oc apply -f - <<EOF
apiVersion: route.openshift.io/v1
kind: Route
metadata:
  name: router-service1
  annotations:
    haproxy.router.openshift.io/rewrite-target: '/i532/app/#'
spec:
  path: '/I532/'
  port:
    targetPort: 8676
  to:
    kind: Service
    name: route-service1
EOF
