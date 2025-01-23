#!/bin/bash

domain=$(oc get ingresses.config/cluster -o jsonpath={.spec.domain})
export nlb_domain="nlb2.${domain:5}"

oc apply -f - <<EOF
apiVersion: operator.openshift.io/v1
kind: IngressController
metadata:
  name: nlb-external
  namespace: openshift-ingress-operator
spec:
  domain: $nlb_domain
  routeSelector:
    matchLabels:
      type: nlb
  replicas: 1
  endpointPublishingStrategy:
    loadBalancer:
      scope: External
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
