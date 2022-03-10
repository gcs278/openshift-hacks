#!/bin/bash
# Replace the default router with hostnetwork
# You can't make another one because it conflicts with default

oc replace --force --wait --filename - <<EOF
apiVersion: operator.openshift.io/v1
kind: IngressController
metadata:
  namespace: openshift-ingress-operator
  name: default
spec:
  endpointPublishingStrategy:
    type: HostNetwork
EOF
oc patch -n openshift-ingress-operator ingresscontroller/default --patch='{"spec": {"replicas": 2}}' --type=merge
sleep 5
oc delete -n openshift-ingress deployment/router-default
oc -n openshift-ingress get deployment/router-default -o yaml

