#!/bin/bash

#oc patch -n openshift-ingress-operator ingresscontroller/default --type merge --patch='{"metadata":{"annotations": {"ingress.operator.openshift.io/auto-delete-load-balancer":""}}}'

echo "Switching default ingress controller to NLB..."
oc patch -n openshift-ingress-operator ingresscontroller/default --type merge --patch='{"spec":{"endpointPublishingStrategy":{"loadBalancer":{"scope":"External","providerParameters":{"type":"AWS","aws":{"type":"NLB"}}},"type":"LoadBalancerService"}}}'
