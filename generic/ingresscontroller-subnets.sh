#!/bin/bash

#domain=$(oc get ingresses.config/cluster -o jsonpath={.spec.domain})
domain=$(oc get dnses cluster -o jsonpath={.spec.baseDomain})
export test_domain="subnets.${domain}"

subnets=$(oc get machinesets.machine.openshift.io -A -o yaml | grep -i subnet-private | awk '{print $2}' | sed 's/private/public/g')

oc apply -f - <<EOF
apiVersion: operator.openshift.io/v1
kind: IngressController
metadata:
  name: subnets
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
            subnets:
              names:
$(echo "${subnets}" | awk '{print "              - "$0}')
  nodePlacement:
    nodeSelector:
      matchLabels:
        node-role.kubernetes.io/worker: ""
EOF
