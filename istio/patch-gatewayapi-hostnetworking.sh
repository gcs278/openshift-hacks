#!/bin/bash

rs=$(oc get replicasets.apps -n gwapi | grep -i 'gateway-' | awk '{print $1}' | head -1)
if [[ "$rs" == "" ]]; then
  echo "ERROR: Couldn't get gateway api gateway replicaset"
  exit 1
fi
oc -n gwapi patch replicaset/${rs} --type=strategic --patch='{"spec":{"template":{"spec":{"containers":[{"name":"istio-proxy","ports":[{"containerPort":"80","hostPort":"80","protocol":"TCP"},{"containerPort":"443","hostPort":"443","protocol":"TCP"}]}],"serviceAccount":"istio-ingressgateway-service-account","serviceAccountName":"istio-ingressgateway-service-account"}}}}'
oc adm policy add-scc-to-user privileged -n gwapi -z istio-ingressgateway-service-account

