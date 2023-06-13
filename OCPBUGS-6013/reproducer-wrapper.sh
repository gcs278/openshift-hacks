#!/bin/bash

COUNT=0
while true; do
  ./reproducer.sh
  COUNT=COUNT+1
  echo "RAN $COUNT successful reproducers!"
done
