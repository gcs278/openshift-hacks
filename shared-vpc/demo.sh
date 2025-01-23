#!/bin/bash

# Install ExternalDNS Operator via UI

# Get RoleARN for Account A
oc get dnses -o yaml

# Create ExternalDNS object with Assume Role
oc apply -f - <<EOF
apiVersion: externaldns.olm.openshift.io/v1beta1
kind: ExternalDNS
metadata:
  name: sample-aws
spec:
  provider:
    type: AWS
    aws:
      assumeRole:
        arn: arn:aws:iam::176500231253:role/gspence-rol1 # Add RoleARN
  source:
    hostnameAnnotation: Allow
    type: Service
EOF

# Annotate the router default service to create a DNS record
oc annotate service -n openshift-ingress router-default external-dns.alpha.kubernetes.io/hostname=externaldns.apps.gspence-demovpc2.devcluster.openshift.com

# Look at DNS records in Route53
