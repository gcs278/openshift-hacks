#!/bin/bash

cat << EOF
apiVersion: operator.openshift.io/v1
kind: IngressController
metadata:
  name: demo
  namespace: openshift-ingress-operator
spec:
  domain: $TEST_DOMAIN
  replicas: 0
  endpointPublishingStrategy:
    type: LoadBalancerService
    loadBalancer:
      DNSManagementPolicy: Managed
      scope: External
      providerParameters:
        type: AWS
        aws:
          type: Classic
          classicLoadBalancer:
            subnets:
              names:
$(echo "${SUBNETS}" | awk '{print "              - "$0}')
  nodePlacement:
    nodeSelector:
      matchLabels:
        node-role.kubernetes.io/worker: ""
EOF
