#!/bin/bash
set -e

BASE_DOMAIN=$(oc get dnses cluster -o jsonpath={.spec.baseDomain})

IC=dns-propagate
I=0

function digTest() {
  DOMAIN=$1
  LABEL=$2
  RESOLVER=$3
  dig=$(dig +short $RESOLVER $DOMAIN)
  if [[ "$dig" != "" ]]; then
    dig=$(echo "$dig" | tr '\n' ',')
    duration=$(( SECONDS - start ))
    echo "${LABEL}: Success in $duration seconds ${DOMAIN}: $dig"
    return 0
  echo
    echo "FAILURE!"
  fi
  return 1
}

COREDNS_IP=$(oc get svc -n openshift-dns dns-default -o jsonpath='{.spec.clusterIP}')
if [[ "$COREDNS_IP" == "" ]]; then
  echo "ERROR: Failed to get coredns ip!"
  exit 1
fi

while true; do
  start=$SECONDS
  TEST_DOMAIN="${IC}-${I}.${BASE_DOMAIN}"
  if oc get ingresscontroller -n openshift-ingress-operator $IC &> /dev/null; then
    echo "Deleting ingresscontroller ${IC}..."
    oc delete -n openshift-ingress-operator ingresscontroller $IC
  fi

  echo "Creating ingresscontroller ${IC}..."
  oc apply -f - <<EOF
  apiVersion: operator.openshift.io/v1
  kind: IngressController
  metadata:
    name: $IC
    namespace: openshift-ingress-operator
  spec:
    domain: $TEST_DOMAIN
    replicas: 0
    endpointPublishingStrategy:
      type: LoadBalancerService
      loadBalancer:
        DNSManagementPolicy: Managed
        scope: External
    nodePlacement:
      nodeSelector:
        matchLabels:
          node-role.kubernetes.io/worker: ""
EOF

  echo "$IC created"
  STATIC_DOMAIN=static.${TEST_DOMAIN}
  echo "Testing static ($STATIC_DOMAIN) and dynamic domains..."
  RESOLVED=(false false false false false)
  STATIC_DOMAIN_RESOLVED=false
  DYNAMIC_DOMAIN_RESOLVED=false
  GOOGLE_STATIC_DOMAIN_RESOLVED=false
  while [[ ${RESOLVED[*]} =~ false ]]; do
    
    if [[ "${RESOLVED[0]}" == "false" ]]; then
      if digTest $STATIC_DOMAIN "STATIC COREDNS" "@${COREDNS_IP}"; then
        RESOLVED[0]=true
      fi
    fi
    
    DYNAMIC_DOMAIN=dyn$(date +%s).${TEST_DOMAIN}
    if [[ "${RESOLVED[1]}" == "false" ]]; then
      if digTest $DYNAMIC_DOMAIN "DYNAMIC COREDNS" "@${COREDNS_IP}"; then
        RESOLVED[1]=true
      fi
    fi
    
    if [[ "${RESOLVED[2]}" == "false" ]]; then
      if digTest $STATIC_DOMAIN "STATIC UPSTREAM DIRECT"; then
        RESOLVED[2]=true
      fi
    fi

    if [[ "${RESOLVED[3]}" == "false" ]]; then
      if digTest $DYNAMIC_DOMAIN "DYNAMIC UPSTREAM DIRECT"; then
        RESOLVED[3]=true
      fi
    fi

    if [[ "${RESOLVED[4]}" == "false" ]]; then
      if digTest $STATIC_DOMAIN "STATIC UPSTREAM 8.8.8.8" "@8.8.8.8"; then
        RESOLVED[4]=true
      fi
    fi

    sleep 3
  done
  echo "SUCCESS Everything resolved"
  I=$((I+1))
done
