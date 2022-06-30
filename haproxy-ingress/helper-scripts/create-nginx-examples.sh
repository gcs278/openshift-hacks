#!/bin/bash

SCRIPT_DIR="$( cd -- "$( dirname -- "${BASH_SOURCE[0]:-$0}"; )" &> /dev/null && pwd 2> /dev/null; )";
YAML_DIR=${SCRIPT_DIR}/../yaml
CERT_DIR=/tmp/haproxy-certs
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

# Set up DNS for istioapi example
DOMAIN="$(oc get ingresscontrollers.operator.openshift.io -n openshift-ingress-operator default -o go-template='{{.status.domain}}')"
export HI_DOMAIN="hi.${DOMAIN:5}"

# Set up certs
# Create CA
test -f ${CERT_DIR}/ca.crt || openssl req -x509 -sha256 -nodes -days 365 -newkey rsa:2048 -subj '/O=RedHat/CN=${ISTIO_DOMAIN}' -keyout ${CERT_DIR}/ca.key -out ${CERT_DIR}/ca.crt

# Certs
create_certs edge "edge.${HI_DOMAIN}" default
create_certs re "re.${HI_DOMAIN}" default
create_certs pass "pass.${HI_DOMAIN}" default

# Configure istioapi examples via istio api
cat ${YAML_DIR}/nginx-gwapi.yaml | envsubst | oc apply -f -
if [[ $? -ne 0 ]]; then
  echo "ERROR: Something went wrong with configuring ${YAML_DIR}/nginx-gwapi.yaml"
  exit 1
fi

echo "Haproxy Ingress:"
echo "curl -I http://http.${HI_DOMAIN}"
echo "curl --cacert ${CERT_DIR}/ca.crt -I https://edge.${HI_DOMAIN}"
echo "curl --cacert ${CERT_DIR}/ca.crt -I https://re.${HI_DOMAIN}"
echo "curl --cacert ${CERT_DIR}/ca.crt -k -I https://pass.${HI_DOMAIN}"
