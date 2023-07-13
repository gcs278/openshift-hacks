#!/bin/bash

domain=$(oc get ingresses.config/cluster -o jsonpath={.spec.domain})
export nlb_domain="nlb.${domain:5}"

oc apply -f - <<EOF
apiVersion: operator.openshift.io/v1
kind: IngressController
metadata:
  name: nlb-shard
  namespace: openshift-ingress-operator
spec:
  domain: $nlb_domain
  routeSelector:
    matchLabels:
      type: nlb
  replicas: 1
  endpointPublishingStrategy:
    loadBalancer:
      scope: Internal
      dnsManagementPolicy: Managed
      providerParameters:
        type: AWS
        aws:
          type: NLB
    type: LoadBalancerService
  nodePlacement:
    nodeSelector:
      matchLabels:
        node-role.kubernetes.io/worker: ""
EOF

oc create namespace test

oc apply -n test -f ./nlb-route-test.yaml

oc apply -f - <<EOF
apiVersion: route.openshift.io/v1
kind: Route
metadata:
  name: route-nlb
  namespace: test
  labels:
    type: nlb
spec:
  host: test.$nlb_domain
  to:
    kind: Service
    name: nlb-test
EOF

while ! oc get route -n test -o json route-nlb | jq '.status' | grep -q nlb-shard; do
  echo "Waiting for route to be admitted..."
  sleep 1
done
echo "Route admitted"

# Get the node that single router pod is on
sameNode=$(oc get pods -n openshift-ingress -l ingresscontroller.operator.openshift.io/deployment-ingresscontroller=nlb-shard -o wide --no-headers | awk '{print $7}')
diffNode=$(oc get nodes --no-headers | grep -v $sameNode | awk '{print $1}' | head -1)

echo "Attempting to curl from a different node...should work"
oc debug node/${diffNode} -- curl test.$nlb_domain --connect-timeout 10

echo "Attempting to curl from the same node...should fail"
oc debug node/${sameNode} -- curl test.$nlb_domain --connect-timeout 10

