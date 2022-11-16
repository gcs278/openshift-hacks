#!/bin/bash

domain=$(oc get ingresses.config/cluster -o jsonpath={.spec.domain})

oc apply -f - <<EOF
apiVersion: operator.openshift.io/v1
kind: IngressController
metadata:
  name: loadbalancer
  namespace: openshift-ingress-operator
spec:
  domain: reproducer.$domain
  endpointPublishingStrategy:
    type: LoadBalancerService
    loadBalancer:
      scope: Internal
  replicas: 1
  nodePlacement:
    nodeSelector:
      matchLabels:
        node-role.kubernetes.io/worker: ""
EOF

sleep 2

#available=$(oc get co ingress --no-headers | awk '{print $4}')
#progressing=$(oc get co ingress --no-headers | awk '{print $4}')
#while [[ "$available" == "False" ]] || [[ "$progressing" == "True" ]] ;do
#  available=$(oc get co ingress --no-headers | awk '{print $3}')
#  progressing=$(oc get co ingress --no-headers | awk '{print $4}')
#  echo "Waiting for loadbalancer. Available=$available Progressing=$progressing"
#  sleep 1
#done

oc patch -n openshift-ingress-operator ingresscontroller/loadbalancer --type merge --patch='{"spec":{"endpointPublishingStrategy":{"loadBalancer":{"scope":"External"}}}}'

sleep 1

#available=$(oc get co ingress --no-headers | awk '{print $4}')
#progressing=$(oc get co ingress --no-headers | awk '{print $4}')
#while [[ "$available" == "False" ]] || [[ "$progressing" == "True" ]] ;do
#  available=$(oc get co ingress --no-headers | awk '{print $3}')
#  progressing=$(oc get co ingress --no-headers | awk '{print $4}')
#  echo "Waiting for loadbalancer. Available=$available Progressing=$progressing"
#  sleep 1
#done

oc delete svc -n openshift-ingress router-loadbalancer

while true; do
  ip=$(oc get svc -n openshift-ingress router-loadbalancer -o jsonpath={.status.loadBalancer.ingress[0].ip})
  if [[ "$ip" != "" ]]; then
    break
  fi
done

while true; do
  curl -I $ip --max-time 2
  if [[ $? -eq 0 ]]; then
     break
  fi
done
