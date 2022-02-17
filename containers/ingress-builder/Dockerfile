FROM registry.access.redhat.com/ubi8/ubi:latest

COPY ./etc-pki-entitlement /etc/pki/entitlement
COPY ./rhsm-ca /etc/rhsm/ca
COPY ./rhsm-conf /etc/rhsm
RUN dnf install -y gcc gdb make openssl-devel pcre-devel zlib-devel diffutils sudo less vim wget strace lsof curl rsyslog procps-ng util-linux socat git
