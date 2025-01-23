#!/bin/bash

cat example.crt example.key > example.pem

#~/src/haproxy.org/haproxy-2.6/haproxy-2.6.13 -f haproxy.config.test 
#~/src/haproxy.org/haproxy-2.8/haproxy-2.8.10 -f haproxy.config.test 
#~/src/haproxy.org/haproxy-2.6/haproxy-2.6.14 -f haproxy.config.real
/home/gspence/src/haproxy.org/haproxy-2.6/haproxy-2.6.18 -c -f haproxy.config.test -db
#/home/gspence/src/haproxy.org/haproxy-2.2/haproxy-2.2.24 -c -f haproxy.config.test 
