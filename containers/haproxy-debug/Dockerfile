# -*- mode: dockerfile -*-

#
# This is the HAProxy router for OpenShift Origin.
#
# The standard name for this image is openshift/origin-haproxy-router
#
FROM quay.io/openshift/origin-haproxy-router:4.8 as openshift-router
USER 0

FROM quay.io/gspence/ingress-builder
# Run as USER 0 required for setcap
USER 0
RUN  mkdir -p /var/lib/haproxy/router/{certs,cacerts,whitelists} && \
     mkdir -p /var/lib/haproxy/{conf/.tmp,run,bin,log} && \
    touch /var/lib/haproxy/conf/{{os_http_be,os_edge_reencrypt_be,os_tcp_be,os_sni_passthrough,os_route_http_redirect,cert_config,os_wildcard_domain}.map,haproxy.config}

COPY --from=openshift-router /usr/bin/openshift-router /usr/bin/
COPY --from=openshift-router /usr/sbin/haproxy /usr/sbin/
COPY --from=openshift-router /var/lib/haproxy /var/lib/haproxy

RUN chown -R :0 /var/lib/haproxy && \
    chmod -R g+w /var/lib/haproxy

WORKDIR /
RUN git clone https://github.com/frobware/haproxy-openshift.git
RUN git clone http://git.haproxy.org/git/haproxy-1.8.git
RUN git clone http://git.haproxy.org/git/haproxy-2.0.git
RUN git clone http://git.haproxy.org/git/haproxy-2.2.git
RUN git clone http://git.haproxy.org/git/haproxy-2.4.git
RUN for i in 1.8 2.0 2.2 2.4; do \
      cp /haproxy-openshift/build-haproxy-${i}.sh /haproxy-${i}; \
    done

USER 1001
EXPOSE 80 443
WORKDIR /var/lib/haproxy/conf
ENV TEMPLATE_FILE=/var/lib/haproxy/conf/haproxy-config.template \
    RELOAD_SCRIPT=/var/lib/haproxy/reload-haproxy
ENTRYPOINT ["/usr/bin/openshift-router", "--v=2"]
