#!/bin/bash

dnsperf -s 127.0.0.1 -p 5053 -d dnsperf.conf -n 10000000 -T 40
