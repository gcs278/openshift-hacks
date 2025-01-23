#!/bin/bash

domain=$(oc get dnses cluster -o jsonpath={.spec.baseDomain})
export test_domain="eip.${domain}"

oc apply -f - <<EOF
apiVersion: operator.openshift.io/v1
kind: IngressController
metadata:
  name: eip
  namespace: openshift-ingress-operator
spec:
  domain: $test_domain
  replicas: 1
  endpointPublishingStrategy:
    type: LoadBalancerService
    loadBalancer:
      scope: External
      providerParameters:
        type: AWS
        aws:
          type: NLB
          networkLoadBalancer:
            eipAllocations:
            - eipalloc-02afb8a95788e2cc6
            - eipalloc-0c140bace00ee207f
            - eipalloc-040b45d88fbec417c
  nodePlacement:
    nodeSelector:
      matchLabels:
        node-role.kubernetes.io/worker: ""
EOF
