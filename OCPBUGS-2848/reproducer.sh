#!/bin/bash

domain=$(oc get ingresses.config/cluster -o jsonpath={.spec.domain})

oc apply -f - <<EOF
apiVersion: operator.openshift.io/v1
kind: IngressController
metadata:
  name: sharded
  namespace: openshift-ingress-operator
spec:
  domain: reproducer.$domain
  routeSelector:
    matchLabels:
      type: shard
    matchExpressions:
    - key: type-test
      operator: In
      values:
      - shard-test
  replicas: 1
  nodePlacement:
    nodeSelector:
      matchLabels:
        node-role.kubernetes.io/worker: ""
EOF

oc create namespace shard
oc label --overwrite=true namespace shard type=shard

oc apply -f - <<EOF
apiVersion: route.openshift.io/v1
kind: Route
metadata:
  name: route-shard
  namespace: shard
  labels:
    type: shard
    type-test: shard-test
spec:
  to:
    kind: Service
    name: router-shard
EOF

sleep 3

while ! oc get route -n shard -o json route-shard | jq '.status' | grep -q sharded; do
  echo "Waiting for route to be admitted..."
  sleep 1
done
echo "Route admitted"
