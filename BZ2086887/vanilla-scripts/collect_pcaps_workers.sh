#!/bin/bash

DIR=/tmp/pcaps-vanilla
mkdir -p ${DIR}
#rm -f ${DIR}*

workers="$(oc get nodes | grep worker | awk '{print $1}')"

#while true; do
  for i in $(oc get pods | grep dumper | awk '{print $1}'); do
    echo $i
    node=$(oc get pods $i -o wide | awk '{print $7}')
    if echo "$workers" | grep -qi "$node"; then
      echo "Found that $i is on a worker node $node"
      WORKER_DIR=${DIR}/${i}
      mkdir -p $WORKER_DIR
      #WORKER_DIR=${DIR}
      rsync --rsh='oc rsh' -a -b --progress --suffix=-$(date +%s) ${i}:/tmp/ ${WORKER_DIR}/
      if [[ $? -ne 0 ]]; then
	echo "failed to get pcaps from $i"
	continue
      fi
      for j in ${WORKER_DIR}/tcpdump.pcap*; do
	../pcapfix-1.1.7/pcapfix ${j} -k --outfile ${j}.fixed.pcap
	rm -f $j
      done
      mergecap ${WORKER_DIR}/*.fixed.pcap -w ${WORKER_DIR}/$i.pcap
      rm -f ${WORKER_DIR}/*.fixed.pcap
    fi
  done
  round=$((round+1))
#done
