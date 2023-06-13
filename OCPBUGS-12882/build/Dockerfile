FROM quay.io/openshift/origin-haproxy-router:4.11

USER 0
COPY *.rpm /

RUN dnf install -y libasan
RUN rpm -e haproxy22
RUN rpm -Uvh /*.rpm

#COPY haproxy-2* /usr/sbin/haproxy

#COPY haproxy-config.template  /var/lib/haproxy/conf/
#COPY reload-haproxy  /var/lib/haproxy/

RUN setcap 'cap_net_bind_service=ep' /usr/sbin/haproxy && \
    chown -R :0 /var/lib/haproxy && \
    chmod -R g+w /var/lib/haproxy && \
    chmod +x /usr/sbin/haproxy

WORKDIR /var/lib/haproxy/conf
USER 1001
EXPOSE 80 443
