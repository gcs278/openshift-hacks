#!/bin/bash

for i in {1..2}; do
  oc apply -f - <<EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: router-contention${i}
  namespace: openshift-ingress
spec:
  replicas: 1
  selector:
    matchLabels:
      app: contention
  template:
    metadata:
      labels:
        app: contention
    spec:
      env:
      - name: ROUTER_SERVICE_NAME
        value: contention
      containers:
      - name: router
        image: quay.io/openshift-release-dev/ocp-v4.0-art-dev@sha256:19cb49191fc9cc4452407d665aa3c14438630d6fcd2466ca437a1ab0c9f2f4db
        #image: quay.io/openshift-release-dev/ocp-v4.0-art-dev@sha256:edbdeea6fe206af5748b72fbf885cfd1a7c7df003677d66222a237e6d8a14d50
        #image: quay.io/gspence/router:fixedresync
        imagePullPolicy: Always
        terminationGracePeriodSeconds: 1  
        command:
          - "/usr/bin/openshift-router"
          - "--v=5"
          - "--resync-interval=1m"
          - "--namespace=default"
          - "--name=contention"
          - "--override-hostname"
          # causes each pod to have a different value
          - "--hostname-template=\${name}-\${namespace}.router-contention${i}.local"
        securityContext:
          allowPrivilegeEscalation: true
          readOnlyRootFilesystem: false
      dnsPolicy: ClusterFirst
      nodeSelector:
        kubernetes.io/os: linux
        node-role.kubernetes.io/worker: ""
      restartPolicy: Always
      securityContext: {}
      serviceAccount: router
      serviceAccountName: router
EOF
done

for i in {1..2}; do
  echo "Waiting for router-contention${i} deployment to rollout"
  oc rollout status -w deployment -n openshift-ingress router-contention${i}
done

echo "Creating route"
oc apply -f - <<EOF
apiVersion: route.openshift.io/v1
kind: Route
metadata:
  name: route-contention
spec:
  port:
    targetPort: 8676
  to:
    kind: Service
    name: route-service1
EOF

while [[ "$contentionHost" == "" ]]; do 
  echo "Waiting for the router to get a status..."
  contentionHost=$(oc get route route-contention -o jsonpath={.status} | jq -r '.ingress[] | select(.routerName  == "contention").host')
  sleep 3
done

echo "Contention host: $contentionHost"
if echo "$contentionHost" | grep -i router-contention1; then
  routerDelete=router-contention1
  routerResync=router-contention2
else
  routerDelete=router-contention2
  routerResync=router-contention1
fi
echo "Deleting $routerDelete..."
oc delete deployment -n openshift-ingress $routerDelete

timeout=0
while [[ "$timeout" -lt 120 ]]; do
  echo "waiting for router to resync, and the status to change to $routerResync"
  contentionHost=$(oc get route route-contention -o jsonpath={.status} | jq -r '.ingress[] | select(.routerName  == "contention").host')
  if echo "$contentionHost" | grep -qi "$routerResync"; then
    echo "Success: Found status changed to $routerResync, no bug"
    exit 0
  fi
  sleep 1
  timeout=$((timeout+1))
done

echo "Failure: Route status never changed to $routerResync, there's a bug"
