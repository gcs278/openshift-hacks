#!/bin/bash 

DOMAIN="$(oc get ingresscontrollers.operator.openshift.io -n openshift-ingress-operator default -o go-template='{{.status.domain}}')"
export ISTIO_DOMAIN="istio.${DOMAIN:5}"
export GWAPI_DOMAIN="gwapi.${DOMAIN:5}"

DOMAINS="${ISTIO_DOMAIN} ${GWAPI_DOMAIN}"
TERMINATIONS="http edge re pass"
for j in ${DOMAINS}; do
  echo "##### $j #####"
  for i in ${TERMINATIONS}; do
    PROTO="https"
    if [[ "${i}" == "http" ]]; then
      PROTO="${i}"
    fi
    cmd="curl -k -sS -I ${PROTO}://${i}.${j}"
    echo $cmd
    echo -n " -> "
    $cmd | head -1
  done
done

echo "##### Console Route #####"
cmd="curl -k -sS -I https://console-openshift-console.${DOMAIN}"
echo $cmd
echo -n " -> "
$cmd | head -1
