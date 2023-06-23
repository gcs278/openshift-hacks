#!/bin/bash

#domain=$(oc get ingresses.config/cluster -o jsonpath={.spec.domain})
domain=$(oc get dnses cluster -o jsonpath={.spec.baseDomain})
export test_domain="internal.${domain}"

oc apply -f - <<EOF
apiVersion: operator.openshift.io/v1
kind: IngressController
metadata:
  name: internal
  namespace: openshift-ingress-operator
spec:
  domain: $test_domain
  replicas: 1
  endpointPublishingStrategy:
    type: LoadBalancerService
    loadBalancer:
      DNSManagementPolicy: Managed
      scope: Internal
  nodePlacement:
    nodeSelector:
      matchLabels:
        node-role.kubernetes.io/worker: ""
EOF
