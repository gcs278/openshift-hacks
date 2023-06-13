#!/bin/bash

#domain=$(oc get ingresses.config/cluster -o jsonpath={.spec.domain})
domain=$(oc get dnses cluster -o jsonpath={.spec.baseDomain})
export test_domain="test2.${domain}"

oc apply -f - <<EOF
apiVersion: operator.openshift.io/v1
kind: IngressController
metadata:
  name: test
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
