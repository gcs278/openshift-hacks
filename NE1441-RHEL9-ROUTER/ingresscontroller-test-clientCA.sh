#!/bin/bash

oc delete configmap -n openshift-config  clientca-cert
oc create configmap -n openshift-config  clientca-cert --from-file=ca-bundle.pem=exampleca.crt

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
  clientTLS:
    clientCA:
      name: clientca-cert
    clientCertificatePolicy: Required
EOF