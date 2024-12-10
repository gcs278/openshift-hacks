#!/bin/bash

cat example.crt exampleca.crt > example-combo.crt
#cat exampleca.crt example.crt > example-combo.crt
oc delete secret -n openshift-ingress router-cert
oc create secret -n openshift-ingress tls router-cert --key=example.key --cert=example-combo.crt

#domain=$(oc get ingresses.config/cluster -o jsonpath={.spec.domain})
domain=$(oc get dnses cluster -o jsonpath={.spec.baseDomain})
export test_domain="demo.${domain}"

oc apply -f - <<EOF
apiVersion: operator.openshift.io/v1
kind: IngressController
metadata:
  name: demo
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
  defaultCertificate:
    name: router-cert
EOF
