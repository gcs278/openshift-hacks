#!/bin/bash
set -e

BASE_DOMAIN=$(oc get dnses cluster -o jsonpath={.spec.baseDomain})

IC=dns-propagate
I=0

function cleanup() {
  oc delete ingresscontroller -n openshift-ingress-operator $IC
  exit 0
}

trap cleanup EXIT

function digTest() {
  DOMAIN=$1
  LABEL=$2
  RESOLVER=$3
  dig=$(dig +tries=1 +time=5 +short $RESOLVER $DOMAIN)
  if [[ "$dig" != "" ]]; then
    dig=$(echo "$dig" | tr '\n' ',')
    duration=$(( SECONDS - start ))
    # durtion after lb ready let's us measure the "true" negative cache
    # the LB has to provision first, then the DNS record is made, so it's a more accurate representation of the negative cache.
    duration_after_lb_ready=$(( duration - lb_ready_duration))
    echo "${LABEL}: Success: total=${duration}s, after_lb_provision=${duration_after_lb_ready}s ${DOMAIN}: $dig"
    return 0
  #else
  #  echo "${LABEL}: FAILURE!"
  fi
  return 1
}

COREDNS_IP=$(oc get svc -n openshift-dns dns-default -o jsonpath='{.spec.clusterIP}')
if [[ "$COREDNS_IP" == "" ]]; then
  echo "ERROR: Failed to get coredns ip!"
  exit 1
fi

DEFAULT_DNS_NS=$(grep "nameserver" /etc/resolv.conf  | awk '{print $2}' |  paste -s -d, -)
while oc get svc -n openshift-ingress router-$IC &> /dev/null; do
  echo "Waiting for service router-$IC to be cleaned up..."
  sleep 10
done

while true; do
  start=$SECONDS
  TEST_DOMAIN="${IC}-${I}.${BASE_DOMAIN}"
  if oc get ingresscontroller -n openshift-ingress-operator $IC &> /dev/null; then
    echo "Deleting ingresscontroller ${IC}..."
    oc delete -n openshift-ingress-operator ingresscontroller $IC
    while oc get svc -n openshift-ingress router-$IC &> /dev/null; do
      echo "Waiting for service router-$IC to be cleaned up..."
      sleep 10
    done
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
  RESOLVED=(false false false false false false false)
  STATIC_DOMAIN_RESOLVED=false
  DYNAMIC_DOMAIN_RESOLVED=false
  GOOGLE_STATIC_DOMAIN_RESOLVED=false
  lb_ready_duration=""
  while [[ ${RESOLVED[*]} =~ false ]]; do
    if [[ "$lb_ready_duration" == "" ]] && [[ $(oc get svc -n openshift-ingress router-$IC -o jsonpath={.status.loadBalancer.ingress[0]}) != "" ]]; then
      lb_ready_duration=$(( SECONDS - start ))
      lb_hostname=$(oc get svc -n openshift-ingress router-$IC -o jsonpath={.status.loadBalancer.ingress[0].hostname})
      echo "LoadBalancer finished provisioning after $lb_ready_duration seconds"
    fi
    
    if [[ "${RESOLVED[0]}" == "false" ]]; then
      if digTest $STATIC_DOMAIN "STATIC COREDNS @${COREDNS_IP}" "@${COREDNS_IP}"; then
        RESOLVED[0]=true
      fi
    fi
    
    DYNAMIC_DOMAIN=dyn$(date +%s).${TEST_DOMAIN}
    if [[ "${RESOLVED[1]}" == "false" ]]; then
      if digTest $DYNAMIC_DOMAIN "DYNAMIC COREDNS @${COREDNS_IP}" "@${COREDNS_IP}"; then
        RESOLVED[1]=true
      fi
    fi
    
    if [[ "${RESOLVED[2]}" == "false" ]]; then
      if digTest $STATIC_DOMAIN "STATIC DEFAULT @$DEFAULT_DNS_NS"; then
        RESOLVED[2]=true
      fi
    fi

    if [[ "${RESOLVED[3]}" == "false" ]]; then
      if digTest $DYNAMIC_DOMAIN "DYNAMIC DEFAULT @$DEFAULT_DNS_NS"; then
        RESOLVED[3]=true
      fi
    fi

    if [[ "${RESOLVED[4]}" == "false" ]]; then
      if digTest $STATIC_DOMAIN "STATIC UPSTREAM @8.8.8.8" "@8.8.8.8"; then
        RESOLVED[4]=true
      fi
    fi

    if [[ "${RESOLVED[5]}" == "false" ]] && [[ "$lb_hostname" != "" ]]; then
      if digTest $lb_hostname "LB_ADDRESS DEFAULT @$DEFAULT_DNS_NS"; then
        RESOLVED[5]=true
      fi
    fi

    if [[ "${RESOLVED[6]}" == "false" ]] && [[ "$lb_hostname" != "" ]]; then
      if digTest $lb_hostname "LB_ADDRESS COREDNS @${COREDNS_IP}" "@${COREDNS_IP}"; then
        RESOLVED[6]=true
      fi
    fi

    sleep 3
  done
  echo "SUCCESS Everything resolved"
  I=$((I+1))
done
