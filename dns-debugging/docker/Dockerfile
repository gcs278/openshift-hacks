FROM quay.io/openshift/origin-coredns:4.11

#USER 0
#COPY *.rpm /


COPY coredns /usr/bin/

#COPY haproxy-config.template  /var/lib/haproxy/conf/

#RUN setcap 'cap_net_bind_service=ep' /usr/sbin/haproxy && \
#    chown -R :0 /var/lib/haproxy && \
#    chmod -R g+w /var/lib/haproxy && \
#    chmod +x /usr/sbin/haproxy

#WORKDIR /var/lib/haproxy/conf
#USER 1001
#EXPOSE 80 443
