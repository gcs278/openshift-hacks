#!/bin/bash
for i in {1..4004}; do
echo -e "backend dynamic${i}\n      mode http\n      balance leastconn\n      retries 2\n      option redispatch\n      timeout connect 5s\n      timeout server 30s\n      timeout queue 30s\n      option httpchk HEAD /login.php\n      cookie DYNSRV insert indirect nocache\n      fullconn 4000\n      server          dynsrv1 192.168.1.1:80 minconn 50 maxconn 500 cookie s1 check inter 1000" >> examples/content-sw-sample.cfg.leastconn;
done

