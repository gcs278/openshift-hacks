#!/bin/bash

oc apply -f - <<EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: haproxy-reproducer
  namespace: openshift-ingress
spec:
  minReadySeconds: 30
  progressDeadlineSeconds: 600
  replicas: 1
  revisionHistoryLimit: 10
  selector:
    matchLabels:
      app: haproxy-reproducer
  strategy:
    rollingUpdate:
      maxSurge: 25%
      maxUnavailable: 50%
    type: RollingUpdate
  template:
    metadata:
      annotations:
        target.workload.openshift.io/management: '{"effect": "PreferredDuringScheduling"}'
      creationTimestamp: null
      labels:
        app: haproxy-reproducer
    spec:
      affinity:
        nodeAffinity:
          requiredDuringSchedulingIgnoredDuringExecution:
            nodeSelectorTerms:
            - matchExpressions:
              - key: node.openshift.io/remote-worker
                operator: NotIn
                values:
                - ""
      containers:
      - env:
        - name: DEFAULT_CERTIFICATE_DIR
          value: /etc/pki/tls/private
        - name: DEFAULT_DESTINATION_CA_PATH
          value: /var/run/configmaps/service-ca/service-ca.crt
        - name: RELOAD_INTERVAL
          value: 5s
        - name: ROUTER_ALLOW_WILDCARD_ROUTES
          value: "false"
        - name: ROUTER_CANONICAL_HOSTNAME
          value: router-default.apps.ocp-c2.prod.psi.redhat.com
        - name: ROUTER_CIPHERS
          value: ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384:ECDHE-ECDSA-CHACHA20-POLY1305:ECDHE-RSA-CHACHA20-POLY1305
        - name: ROUTER_CIPHERSUITES
          value: TLS_AES_128_GCM_SHA256:TLS_AES_256_GCM_SHA384:TLS_CHACHA20_POLY1305_SHA256
        - name: ROUTER_DISABLE_HTTP2
          value: "false"
        - name: ROUTER_DISABLE_NAMESPACE_OWNERSHIP_CHECK
          value: "true"
        - name: ROUTER_DOMAIN
          value: apps.ocp-c2.prod.psi.redhat.com
        - name: ROUTER_LOAD_BALANCE_ALGORITHM
          value: random
        - name: ROUTER_METRICS_TLS_CERT_FILE
          value: /etc/pki/tls/metrics-certs/tls.crt
        - name: ROUTER_METRICS_TLS_KEY_FILE
          value: /etc/pki/tls/metrics-certs/tls.key
        - name: ROUTER_METRICS_TYPE
          value: haproxy
        - name: ROUTER_SERVICE_HTTPS_PORT
          value: "443"
        - name: ROUTER_SERVICE_HTTP_PORT
          value: "80"
        - name: ROUTER_SERVICE_NAME
          value: default
        - name: ROUTER_SERVICE_NAMESPACE
          value: openshift-ingress
        - name: ROUTER_SET_FORWARDED_HEADERS
          value: append
        - name: ROUTER_TCP_BALANCE_SCHEME
          value: source
        - name: ROUTER_THREADS
          value: "4"
        - name: SSL_MIN_VERSION
          value: TLSv1.2
        - name: STATS_PASSWORD_FILE
          value: /var/lib/haproxy/conf/metrics-auth/statsPassword
        - name: STATS_PORT
          value: "1936"
        - name: STATS_USERNAME_FILE
          value: /var/lib/haproxy/conf/metrics-auth/statsUsername
        image: quay.io/gspence/router:OCPBUGS12882-2.2.29
        imagePullPolicy: IfNotPresent
        livenessProbe:
          failureThreshold: 3
          httpGet:
            path: /healthz
            port: 1936
            scheme: HTTP
          periodSeconds: 10
          successThreshold: 1
          terminationGracePeriodSeconds: 10
          timeoutSeconds: 1
        name: router
        ports:
        - containerPort: 80
          name: http
          protocol: TCP
        - containerPort: 443
          name: https
          protocol: TCP
        - containerPort: 1936
          name: metrics
          protocol: TCP
        readinessProbe:
          failureThreshold: 3
          httpGet:
            path: /healthz/ready
            port: 1936
            scheme: HTTP
          periodSeconds: 10
          successThreshold: 1
          timeoutSeconds: 1
        resources:
          requests:
            cpu: 100m
            memory: 256Mi
        securityContext:
          allowPrivilegeEscalation: true
        startupProbe:
          failureThreshold: 120
          httpGet:
            path: /healthz/ready
            port: 1936
            scheme: HTTP
          periodSeconds: 1
          successThreshold: 1
          timeoutSeconds: 1
        terminationMessagePath: /dev/termination-log
        terminationMessagePolicy: FallbackToLogsOnError
        volumeMounts:
        - mountPath: /etc/pki/tls/private
          name: default-certificate
          readOnly: true
        - mountPath: /var/run/configmaps/service-ca
          name: service-ca-bundle
          readOnly: true
        - mountPath: /var/lib/haproxy/conf/metrics-auth
          name: stats-auth
          readOnly: true
        - mountPath: /etc/pki/tls/metrics-certs
          name: metrics-certs
          readOnly: true
        - mountPath: /var/run/secrets/kubernetes.io/serviceaccount
          name: kube-api-access-2xk8f
          readOnly: true
      dnsPolicy: ClusterFirstWithHostNet
      imagePullSecrets:
      - name: router-dockercfg-9wzsf
      nodeSelector:
        node-role.kubernetes.io/worker: ""
      priorityClassName: system-cluster-critical
      restartPolicy: Always
      schedulerName: default-scheduler
      securityContext: {}
      serviceAccount: router
      serviceAccountName: router
      terminationGracePeriodSeconds: 3600
      serviceAccount: router
      serviceAccountName: router
      volumes:
      - name: default-certificate
        secret:
          defaultMode: 420
          secretName: custom-cert
      - configMap:
          defaultMode: 420
          items:
          - key: service-ca.crt
            path: service-ca.crt
          name: service-ca-bundle
          optional: false
        name: service-ca-bundle
      - name: stats-auth
        secret:
          defaultMode: 420
          secretName: router-stats-default
      - name: metrics-certs
        secret:
          defaultMode: 420
          secretName: router-metrics-certs-default
      - name: kube-api-access-2xk8f
        projected:
          defaultMode: 420
          sources:
          - serviceAccountToken:
              expirationSeconds: 3607
              path: token
          - configMap:
              items:
              - key: ca.crt
                path: ca.crt
              name: kube-root-ca.crt
          - downwardAPI:
              items:
              - fieldRef:
                  apiVersion: v1
                  fieldPath: metadata.namespace
                path: namespace
          - configMap:
              items:
              - key: service-ca.crt
                path: service-ca.crt
              name: openshift-service-ca.crt
EOF

IP=$(oc get pod -l app=haproxy-reproducer -n openshift-ingress --no-headers -o jsonpath="{.items[*].status.podIP}")

CANARY=$(oc get route -n openshift-ingress-canary canary -o go-template={{.spec.host}})
CONSOLE=$(oc get route -n openshift-console console -o go-template={{.spec.host}})

echo "Test this pod via by running this inside of your cluster (e.g. oc debug):"
echo "curl -H \"Host: ${CONSOLE}\" $IP"
