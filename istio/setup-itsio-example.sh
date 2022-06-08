#!/bin/bash

oc adm policy add-scc-to-group anyuid system:serviceaccounts:istio-system

DOWNLOAD_DIR="/tmp/istio-download"

rm -rf ${DOWNLOAD_DIR}
mkdir -p ${DOWNLOAD_DIR}

# Download istio
cd ${DOWNLOAD_DIR}
curl -L https://istio.io/downloadIstio | sh -
if [[ $? -ne 0 ]]; then
  echo "ERROR: Failed to download istio"
  exit 1
fi
cd - > /dev/null

istioctl=$(find ${DOWNLOAD_DIR} -iname "istioctl" | head -1)
if [[ ! -f "$istioctl" ]]; then
  echo "ERROR: can't find istioctl at: $istioctl"
  exit 1
fi

# Install Istio
$istioctl install -y --set profile=openshift --set meshConfig.accessLogFile=/dev/stdout

# Expose openshift route for istio
oc -n istio-system expose svc/istio-ingressgateway --port=http2

DNS_RECORD_TYPE="CNAME"
INGRESS_HOST=$(oc -n istio-system get service istio-ingressgateway -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
if [[ "$INGRESS_HOST" == "" ]]; then
  INGRESS_HOST=$(oc -n istio-system get service istio-ingressgateway -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
  DNS_RECORD_TYPE="A"
fi
if [[ "$INGRESS_HOST" == "" ]]; then
  echo "ERROR: There was an issue getting the istio ingress service hostname or ip"
  exit 1
fi
INGRESS_PORT=$(oc -n istio-system get service istio-ingressgateway -o jsonpath='{.spec.ports[?(@.name=="http2")].port}')

DOMAIN="$(oc get ingresscontrollers.operator.openshift.io -n openshift-ingress-operator default -o go-template='{{.status.domain}}')"
ISTIO_DOMAIN="*.istio.${DOMAIN:5}"
ISTIO_GWAPI_DOMAIN="*.gwapi.${DOMAIN:5}"

# Add wildcard to send dns requests to istio via istio api
oc apply -f - <<EOF
apiVersion: ingress.operator.openshift.io/v1
kind: DNSRecord
metadata:
  name: istio-wildcard
  namespace: openshift-ingress-operator
  labels:
    ingresscontroller.operator.openshift.io/owning-ingresscontroller: default
spec:
  dnsName: "${ISTIO_DOMAIN}."
  recordTTL: 30
  recordType: ${DNS_RECORD_TYPE}
  targets:
  - ${INGRESS_HOST}
EOF

# Clear certs 
rm -rf /tmp/istio-certs

# Configure nginx examples
./create-nginx-examples.sh

# Convert the console route to istio ingress
./convert-console-route.sh
