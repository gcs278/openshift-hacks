#!/bin/bash

INGRESS_HOST=$(oc -n istio-system get service istio-ingressgateway -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
INGRESS_PORT=$(oc -n istio-system get service istio-ingressgateway -o jsonpath='{.spec.ports[?(@.name=="http2")].port}')

CONSOLE_ROUTE="$(oc get routes -n openshift-console console -o go-template='{{.spec.host}}')"

echo "Converting $CONSOLE_ROUTE to istio"
oc apply -f - <<EOF
apiVersion: ingress.operator.openshift.io/v1
kind: DNSRecord
metadata:
  name: istio-console
  namespace: openshift-ingress-operator
  labels:
    ingresscontroller.operator.openshift.io/owning-ingresscontroller: default
spec:
  dnsName: "${CONSOLE_ROUTE}."
  recordTTL: 30
  recordType: CNAME
  targets:
  - ${INGRESS_HOST}
EOF

# Create virtual service for console route
oc apply -f - <<EOF
apiVersion: networking.istio.io/v1alpha3
kind: VirtualService
metadata:
  name: console
  namespace: openshift-console
spec:
  hosts:
  - ${CONSOLE_ROUTE}
  gateways:
  - console-gateway
  tls:
  - match:
    - port: 443
      sniHosts:
      - ${CONSOLE_ROUTE}
    route:
    - destination:
        port:
          number: 443
        host: console
EOF

# Create the ingressgateway
oc apply -f - <<EOF
apiVersion: networking.istio.io/v1alpha3
kind: Gateway
metadata:
  name: console-gateway
  namespace: openshift-console
spec:
  selector:
    istio: ingressgateway
  servers:
  - port:
      number: 443
      name: https
      protocol: HTTPS
    hosts:
    - ${CONSOLE_ROUTE}
    tls:
      mode: PASSTHROUGH
EOF

echo "Converted console route. Try:"
echo "curl -I -k https://${CONSOLE_ROUTE}"
