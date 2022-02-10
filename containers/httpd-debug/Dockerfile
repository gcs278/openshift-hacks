FROM registry.access.redhat.com/ubi8/ubi:latest

RUN dnf install -y procps-ng gcc iproute httpd curl

copy /httpd.conf /etc/httpd/conf/httpd.conf

COPY index.html /opt/app-root/src/

RUN useradd default

RUN mkdir -p /opt/app-root/src/; touch /run/httpd.pid; chown default:default /run/httpd.pid

ENTRYPOINT ["/usr/sbin/httpd","-DFOREGROUND"]
