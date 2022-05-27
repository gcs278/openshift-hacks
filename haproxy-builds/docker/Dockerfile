FROM quay.io/openshift/origin-haproxy-router:4.11

USER 0
COPY *.rpm /

RUN rpm -e haproxy22
RUN rpm -Uvh /*.rpm
USER 1001
