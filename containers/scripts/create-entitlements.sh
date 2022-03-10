#!/bin/bash

set -e

ENTITLEMENT_SECRET_ARGS=""
for file in $(find /etc/pki/entitlement -mindepth 1 -maxdepth 1 -iname "*.pem"); do
  ENTITLEMENT_SECRET_ARGS="${ENTITLEMENT_SECRET_ARGS} --from-file ${file}"
done
if [[ "${ENTITLEMENT_SECRET_ARGS}" == "" ]]; then
  echo "ERROR: No RHEL entitlements. Are you subscribed to RHEL?"
  exit 1
fi

RHSM_CA_ARGS=""
for file in $(find /etc/rhsm/ca -iname "*.pem"); do
  RHSM_CA_ARGS="${RHSM_CA_ARGS} --from-file ${file}"
done
oc create secret --dry-run=client generic etc-pki-entitlement $ENTITLEMENT_SECRET_ARGS -o yaml | oc apply -f -
oc create secret --dry-run=client generic rhsm-ca $RHSM_CA_ARGS -o yaml | oc apply -f -
oc create secret --dry-run=client generic rhsm-conf --from-file=/etc/rhsm/rhsm.conf -o yaml | oc apply -f -
