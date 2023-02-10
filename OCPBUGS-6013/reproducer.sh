#!/bin/bash

oc patch -n openshift-ingress-operator ingresscontroller/default --type merge --patch='{"metadata":{"annotations": {"ingress.operator.openshift.io/auto-delete-load-balancer":""}
}}'

sleep 5

echo "Switching default ingress controller to internal scope..."
oc patch -n openshift-ingress-operator ingresscontroller/default --type merge --patch='{"spec":{"endpointPublishingStrategy":{"loadBalancer":{"scope":"Internal"},"type":"LoadBalancerService"}}}'

while ! oc get svc -n openshift-ingress router-default -o jsonpath={.status.loadBalancer.ingress[0].hostname} | grep -q "^internal-"; do
  echo "Waiting for router-default service to become internal"
  sleep 5
done

sleep 30

echo "Switching default ingress controller to external scope..."
oc patch -n openshift-ingress-operator ingresscontroller/default --type merge --patch='{"spec":{"endpointPublishingStrategy":{"loadBalancer":{"scope":"External"},"type":"LoadBalancerService"}}}'


while oc get svc -n openshift-ingress router-default -o jsonpath={.status.loadBalancer.ingress[0].hostname} | grep -q "^internal-"; do
  echo "Waiting for router-default service to become external"
  sleep 5
done

while [[ $(dig +short "$(oc get svc -n openshift-ingress router-default -o jsonpath={.status.loadBalancer.ingress[0].hostname})") == "" ]]; do
  echo "Waiting for external DNS name $(oc get svc -n openshift-ingress router-default -o jsonpath={.status.loadBalancer.ingress[0].hostname}) to resolve..."
  sleep 5
done

outputCurl=$(curl -sS $(oc get svc -n openshift-ingress router-default -o jsonpath={.status.loadBalancer.ingress[0].hostname}) 2>&1)
RT=$?
while [[ "$RT" != 0 ]]; do
  echo "Curl not working:"
  echo "$outputCurl"
  sleep 5
  outputCurl=$(curl -sS $(oc get svc -n openshift-ingress router-default -o jsonpath={.status.loadBalancer.ingress[0].hostname}) 2>&1)
  RT=$?
done

echo "Curl was successful! No issue found"
