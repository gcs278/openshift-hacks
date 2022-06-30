#!/bin/bash

# Must do this for openshift to allow haproxy-ingress
oc adm policy add-scc-to-group anyuid system:serviceaccounts:ingress-controller
oc adm policy add-scc-to-group anyuid system:serviceaccounts:haproxy-ingress
oc adm policy add-scc-to-user privileged -n ingress-controller -z haproxy-ingress

helm upgrade --install haproxy-ingress haproxy-ingress/haproxy-ingress\
  --create-namespace --namespace ingress-controller \
  --version v0.14.0-alpha.2\
  -f haproxy-ingress-values.yaml

# Install GWAPI
kubectl get crd gateways.gateway.networking.k8s.io &> /dev/null || { kubectl kustomize "github.com/kubernetes-sigs/gateway-api/config/crd?ref=v0.4.0" | kubectl apply -f -; }

# Set up DNS for istioapi example
DOMAIN="$(oc get ingresscontrollers.operator.openshift.io -n openshift-ingress-operator default -o go-template='{{.status.domain}}')"
export HI_DOMAIN="hi.${DOMAIN:5}"

TIMEOUT=60
while true; do
  if [[ "$TIMEOUT" -lt 0 ]]; then
    echo "ERROR: Gateway API loadbalancer never got domain name"
    exit 1
  fi
  DNS_RECORD_TYPE="CNAME"
  INGRESS_HOST=$(oc get service -n ingress-controller haproxy-ingress -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
  if [[ "$INGRESS_HOST" == "" ]]; then
    INGRESS_HOST=$(oc get service -n ingress-controller haproxy-ingress -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
    DNS_RECORD_TYPE="A"
  fi
  if [[ "$INGRESS_HOST" == "" ]]; then
    echo "Waiting for ingress service to get an ip..."
    sleep 1
    TIMEOUT=$((TIMEOUT-1))
  else
    break
  fi
done
if [[ "$INGRESS_HOST" == "" ]]; then
  echo "ERROR: There was an issue getting the istio ingress service hostname or ip"
  exit 1
fi

oc apply -f - <<EOF
apiVersion: ingress.operator.openshift.io/v1
kind: DNSRecord
metadata:
  name: hi-wildcard
  namespace: openshift-ingress-operator
  labels:
    ingresscontroller.operator.openshift.io/owning-ingresscontroller: default
spec:
  dnsName: "*.${HI_DOMAIN}."
  recordTTL: 30
  recordType: ${DNS_RECORD_TYPE}
  targets:
  - ${INGRESS_HOST}
EOF

echo $HI_DOMAIN
rm -rf /tmp/haproxy-certs/
./helper-scripts/create-nginx-examples.sh
