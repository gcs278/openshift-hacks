#!/bin/bash

head -1 $1 | awk -F',' '{print $6}'
cat $1 | grep http  | grep requests_per_second | awk -F',' '{print $6}'
echo
cat $1 | grep http  | grep latency | awk -F',' '{print $6}'
echo
cat $1 | grep edge  | grep requests_per_second | awk -F',' '{print $6}'
echo
cat $1 | grep edge  | grep latency | awk -F',' '{print $6}'
echo
cat $1 | grep passthrough  | grep requests_per_second | awk -F',' '{print $6}'
echo
cat $1 | grep passthrough  | grep latency | awk -F',' '{print $6}'
echo
cat $1 | grep reencrypt  | grep requests_per_second | awk -F',' '{print $6}'
echo
cat $1 | grep reencrypt  | grep latency | awk -F',' '{print $6}'
echo
cat $1 | grep mix  | grep requests_per_second | awk -F',' '{print $6}'
echo
cat $1 | grep mix  | grep latency | awk -F',' '{print $6}'
