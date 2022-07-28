FROM quay.io/openshift/origin-haproxy-router:4.11

USER 0

COPY haproxy-config.template  /var/lib/haproxy/conf/

WORKDIR /var/lib/haproxy/conf
USER 1001
EXPOSE 80 443
