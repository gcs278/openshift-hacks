FROM quay.io/openshift/origin-cli

COPY dns-propagate-test.sh /
RUN chmod +x /dns-propagate-test.sh

ENTRYPOINT /dns-propagate-test.sh
