#!/bin/bash
use-local-pilot() {
  ip=$(/sbin/ip route | awk '/docker0/ { print $9 }')
  kubectl -n istio-system delete svc istiod
  kubectl -n istio-system delete endpoints istiod
  cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Service
metadata:
  name: istiod
  namespace: istio-system
spec:
  ports:
  - name: grpc-xds
    port: 15010
  - name: https-dns
    port: 15012
  - name: https-webhook
    port: 443
    targetPort: 15017
  - name: http-monitoring
    port: 15014
---
apiVersion: v1
kind: Endpoints
metadata:
  name: istiod
  namespace: istio-system
subsets:
- addresses:
  - ip: ${ip}
  ports:
  - name: https-dns
    port: 15012
    protocol: TCP
  - name: grpc-xds
    port: 15010
    protocol: TCP
  - name: https-webhook
    port: 15017
    protocol: TCP
  - name: http-monitoring
    port: 15014
    protocol: TCP

EOF
}

use-local-pilot
