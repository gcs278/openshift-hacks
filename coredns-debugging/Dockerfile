FROM docker.io/library/rockylinux:9

COPY coredns /usr/local/bin/coredns
COPY corefile-upstream /corefile-upstream
COPY hosts.db /hosts.db

ENTRYPOINT ["/usr/local/bin/coredns","-conf","/corefile-upstream"]
