#!/bin/bash
domain=$(oc get ingresses.config/cluster -o jsonpath={.spec.domain})

oc apply -f - <<EOF
apiVersion: operator.openshift.io/v1
kind: IngressController
metadata:
  name: sharded
  namespace: openshift-ingress-operator
spec:
  domain: shard.${domain}
  replicas: 1
  routeSelector:
    matchLabels:
      type: shard
  nodePlacement:
    nodeSelector:
      matchLabels:
        node-role.kubernetes.io/worker: ""
EOF

oc apply -f - <<EOF
apiVersion: route.openshift.io/v1
kind: Route
metadata:
  name: route-shard
  labels:
    type: shard
spec:
  to:
    kind: Service
    name: router-shard
EOF

sleep 3

while ! oc get route -o json route-shard | jq '.status' | grep -q sharded; do
  echo "Waiting for route to be admitted..."
  sleep 1
done
echo "Route admitted"

oc apply -f - <<EOF
apiVersion: route.openshift.io/v1
kind: Route
metadata:
  name: route-shard
  labels:
    type: unshard
spec:
  to:
    kind: Service
    name: router-shard
EOF

sleep 5

while oc get route -o json route-shard | jq '.status' | grep -q sharded; do
  echo "Waiting for route to be un-admitted..."
  sleep 1
done
echo "Route unadmitted"
