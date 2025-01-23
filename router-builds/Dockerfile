FROM registry.ci.openshift.org/ocp/4.15:base as builder
RUN wget -c https://go.dev/dl/go1.21.1.linux-amd64.tar.gz && tar -C /tmp/ -xzf go1.21.1.linux-amd64.tar.gz && rm go1.21.1.linux-amd64.tar.gz
RUN GOPATH=/tmp GOCACHE=/tmp /tmp/go/bin/go install github.com/go-delve/delve/cmd/dlv@latest

FROM quay.io/openshift-release-dev/ocp-v4.0-art-dev@sha256:15f1974647ac40b8fc895474cc6db94a553929020a2492732b49e50e89830d74
COPY --from=builder /tmp/bin/dlv /usr/local/bin/
COPY openshift-router /usr/bin/
