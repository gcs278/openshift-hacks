#!/bin/bash

waitForServiceIP() {
  START1=$(date +%s.%N)
  echo "Waiting for router-$1..."
  while [[ "$(oc get service -n openshift-ingress router-$1 -o jsonpath={.status.loadBalancer.ingress[0]})" == "" ]]; do
    sleep 5
  done
  END1=$(date +%s.%N)
  DIFF1=$(echo "$END1 - $START1" | bc)
  
  echo "Router-${1} took $DIFF1"
}

ICS=15
for i in $(seq 1 $ICS); do
  domain=$(oc get dnses cluster -o jsonpath={.spec.baseDomain})
  export test_domain="demo${i}.${domain}"

  oc apply -f - <<EOF
apiVersion: operator.openshift.io/v1
kind: IngressController
metadata:
  name: demo${i}
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
EOF

done

START=$(date +%s.%N)

for i in $(seq 1 $ICS); do
  waitForServiceIP demo${i} &
done

wait $(jobs -p)

END=$(date +%s.%N)
DIFF=$(echo "$END - $START" | bc)
echo "Total Time: $DIFF"

echo "Cleaning up..."
for i in $(seq 1 $ICS); do
  oc delete ingresscontroller -n openshift-ingress-operator demo${i} &
done

wait $(jobs -p)
