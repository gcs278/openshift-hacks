FROM quay.io/gspence/router-base:OCPBUGS12882

USER 0
#COPY *.rpm /

RUN apt-get update
RUN echo deb http://deb.debian.org/debian bullseye-backports main  > /etc/apt/sources.list.d/backports.list && \
    apt-get update 
    #apt-get -y install haproxy=2.6.\* -t bullseye-backports
# RUN apt-get -y install haproxy=2.2.\*
COPY haproxy-2.8.1-debian /usr/sbin/haproxy
RUN chmod +x /usr/sbin/haproxy
RUN apt-get -y install libcap2-bin
RUN apt-get -y install procps rsyslog util-linux curl libpcre3

#INSTALL_PKGS="haproxy22 rsyslog procps-ng util-linux" && \

RUN mkdir -p /var/lib/haproxy/router/certs && \
    mkdir -p /var/lib/haproxy/router/cacerts && \
    mkdir -p /var/lib/haproxy/router/whitelists && \
    mkdir -p /var/lib/haproxy/conf/.tmp && \
    mkdir -p /var/lib/haproxy/conf/run && \
    mkdir -p /var/lib/haproxy/run && \
    mkdir -p /var/lib/haproxy/conf/bin && \
    mkdir -p /var/lib/haproxy/conf/log && \
    mkdir -p /var/lib/haproxy/conf/mtls && \
    touch /var/lib/haproxy/conf/{{os_http_be,os_edge_reencrypt_be,os_tcp_be,os_sni_passthrough,os_route_http_redirect,cert_config,os_wildcard_domain}.map,haproxy.config} && \
    setcap 'cap_net_bind_service=ep' /usr/sbin/haproxy && \
    chown -R :0 /var/lib/haproxy && \
    chmod -R g+w /var/lib/haproxy
    #sed -i 's/SECLEVEL=2/SECLEVEL=1/g' /etc/crypto-policies/back-ends/opensslcnf.config
COPY haproxy /var/lib/haproxy/

LABEL io.k8s.display-name="OpenShift HAProxy Router" \
      io.k8s.description="This component offers ingress to an OpenShift cluster via Ingress and Route rules." \
      io.openshift.tags="openshift,router,haproxy"
USER 1001
EXPOSE 80 443
WORKDIR /var/lib/haproxy/conf
ENV TEMPLATE_FILE=/var/lib/haproxy/conf/haproxy-config.template \
    RELOAD_SCRIPT=/var/lib/haproxy/reload-haproxy
ENTRYPOINT ["/usr/bin/openshift-router", "--v=2"]
