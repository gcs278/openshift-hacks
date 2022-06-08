#!/bin/bash

DOMAIN="$(oc get ingresscontrollers.operator.openshift.io -n openshift-ingress-operator default -o go-template='{{.status.domain}}')"
export ISTIO_DOMAIN="istio.${DOMAIN:5}"
export GWAPI_DOMAIN="gwapi.${DOMAIN:5}"

CERT_DIR=/tmp/istio-certs
mkdir -p $CERT_DIR

function create_certs() {
  TYPE="$1"
  CERT_DOMAIN="$2"
  NAMESPACE="$3"
  test -f ${CERT_DIR}/${TYPE}.${NAMESPACE}.key || openssl req -out ${CERT_DIR}/${TYPE}.${NAMESPACE}.csr -newkey rsa:2048 -nodes -keyout ${CERT_DIR}/${TYPE}.${NAMESPACE}.key -subj "/CN=${CERT_DOMAIN}/O=RedHat"
  if [[ $? -ne 0 ]]; then
    echo "ERROR: Cert generation for $CERT_DOMAIN failed!"
    exit 1
  fi
  test -f ${CERT_DIR}/${TYPE}.${NAMESPACE}.crt || openssl x509 -req -sha256 -days 365 -CA ${CERT_DIR}/ca.crt -CAkey ${CERT_DIR}/ca.key -set_serial 0 -in ${CERT_DIR}/${TYPE}.${NAMESPACE}.csr -out ${CERT_DIR}/${TYPE}.${NAMESPACE}.crt
  if [[ $? -ne 0 ]]; then
    echo "ERROR: Cert generation for $CERT_DOMAIN failed!"
    exit 1
  fi
  oc delete -n $NAMESPACE secret ${TYPE}-credential 2>/dev/null
  oc create -n $NAMESPACE secret tls ${TYPE}-credential --key=${CERT_DIR}/${TYPE}.${NAMESPACE}.key --cert=${CERT_DIR}/${TYPE}.${NAMESPACE}.crt
}

# Create namespaces
oc create namespace istioapi --dry-run=client -o yaml | oc apply -f -
oc create namespace gwapi  --dry-run=client -o yaml | oc apply --overwrite=true -f -
oc adm policy add-scc-to-group anyuid system:serviceaccounts:istioapi
oc adm policy add-scc-to-group anyuid system:serviceaccounts:gwapi

# Set up certs
# Create CA
test -f ${CERT_DIR}/ca.crt || openssl req -x509 -sha256 -nodes -days 365 -newkey rsa:2048 -subj '/O=RedHat/CN=${ISTIO_DOMAIN}' -keyout ${CERT_DIR}/ca.key -out ${CERT_DIR}/ca.crt

# Istio API Certs
create_certs edge "edge.${ISTIO_DOMAIN}" istio-system
create_certs re "re.${ISTIO_DOMAIN}" istio-system
create_certs pass "pass.${ISTIO_DOMAIN}" istioapi

# Gateway API Certs
create_certs edge "edge.${GWAPI_DOMAIN}" gwapi
create_certs re "re.${GWAPI_DOMAIN}" gwapi
create_certs pass "pass.${GWAPI_DOMAIN}" gwapi

# Install gateway api
kubectl get crd gateways.gateway.networking.k8s.io &> /dev/null || { kubectl kustomize "github.com/kubernetes-sigs/gateway-api/config/crd?ref=v0.4.0" | kubectl apply -f -; }

# Configure istioapi examples via istio api
cat ./nginx-istioapi.yaml | envsubst | oc apply -f -
cat ./nginx-gwapi.yaml | envsubst | oc apply -f -
cat ./echo-service-sleeper-istioapi.yaml | envsubst | oc apply -f -

TIMEOUT=60
while [[ "$GWAPI_LOADBALANCER_DOMAIN" == "" ]] && [[ "$GWAPI_LOADBALANCER_IP" == "" ]]; do
  # For AWS, it uses hostname, but for GCE, it uses IP
  GWAPI_LOADBALANCER_DOMAIN=$(oc -n gwapi get service gateway -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
  GWAPI_LOADBALANCER_IP=$(oc -n gwapi get service gateway -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
  echo "Waiting for gateway api loadbalancer to get domain name"
  if [[ "$TIMEOUT" -lt 0 ]]; then
    echo "ERROR: Gateway API loadbalancer never got domain name"
    exit 1
  fi
  TIMEOUT=$((TIMEOUT-1))
  sleep 1
done

if [[ "$GWAPI_LOADBALANCER_DOMAIN" != "" ]]; then
  GWAPI_LOADBALANCER="$GWAPI_LOADBALANCER_DOMAIN"
  DNS_RECORD_TYPE="CNAME"
else
  GWAPI_LOADBALANCER="$GWAPI_LOADBALANCER_IP"
  DNS_RECORD_TYPE="A"
fi

# Add wildcard to send dns requests to istio via gwapi
oc apply -f - <<EOF
apiVersion: ingress.operator.openshift.io/v1
kind: DNSRecord
metadata:
  name: istio-gwapi-wildcard
  namespace: openshift-ingress-operator
  labels:
    ingresscontroller.operator.openshift.io/owning-ingresscontroller: default
spec:
  dnsName: "*.${GWAPI_DOMAIN}."
  recordTTL: 30
  recordType: ${DNS_RECORD_TYPE}
  targets:
  - ${GWAPI_LOADBALANCER}
EOF


echo "ISITIO API:"
echo "curl -I http://http.${ISTIO_DOMAIN}"
echo "curl --cacert ${CERT_DIR}/ca.crt -I https://edge.${ISTIO_DOMAIN}"
echo "curl --cacert ${CERT_DIR}/ca.crt -I https://re.${ISTIO_DOMAIN}"
echo "curl --cacert ${CERT_DIR}/ca.crt -I https://pass.${ISTIO_DOMAIN}"
echo
echo "GWAPI:"
echo "curl -I http://http.${GWAPI_DOMAIN}"
echo "curl --cacert ${CERT_DIR}/ca.crt -I https://edge.${GWAPI_DOMAIN}"
echo "curl --cacert ${CERT_DIR}/ca.crt -I https://re.${GWAPI_DOMAIN}"
echo "curl --cacert ${CERT_DIR}/ca.crt -I https://pass.${GWAPI_DOMAIN}"
