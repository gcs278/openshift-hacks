#!/bin/bash

DIR=/tmp/pcaps-metadata
mkdir -p ${DIR}

#SYSADM="--as system:admin"

workers="$(oc get nodes $SYSADM | grep worker | awk '{print $1}')"

if [[ "$1" != '' ]]; then
  dumpers="$1"
else
  dumpers=$(oc get pods -n openshift-dns $SYSADM | grep dumper | awk '{print $1}')
fi

for i in $dumpers; do
  echo $i
  node=$(oc get pods $i -o wide -n openshift-dns $SYSADM --no-headers | awk '{print $7}')
  #if echo "$workers" | grep -qi "$node"; then
    echo "Found that $i is on a worker node $node"
    WORKER_DIR=${DIR}/${i}
    mkdir -p $WORKER_DIR
    #WORKER_DIR=${DIR}
    metadata=${WORKER_DIR}/metadata
    echo "This Node: $node" > $metadata
    echo "### DNS Pods: ###" >> $metadata
    oc get pods -n openshift-dns -o wide $SYSADM | grep -i dns >> $metadata
    echo "### Nodes: ###" >> $metadata
    oc get nodes -o wide $SYSADM >> $metadata
    echo "### Pods on $node: ###" >> $metadata
    oc get pods -A $SYSADM -o wide | grep -i $node >> $metadata
    rsync --rsh='oc rsh -n openshift-dns' -a -b --progress --suffix=-$(date +%s) ${i}:/tmp/ ${WORKER_DIR}/
    if [[ $? -ne 0 ]]; then
      echo "failed to get pcaps from $i"
      continue
    fi
    for j in ${WORKER_DIR}/tcpdump.pcap*; do
      ./pcapfix-1.1.7/pcapfix ${j} -k --outfile ${j}.fixed.pcap
      rm -f $j
    done
    mergecap ${WORKER_DIR}/*.fixed.pcap -w ${WORKER_DIR}/$i.pcap
    rm -f ${WORKER_DIR}/*.fixed.pcap
    echo "### Pods on $node (Again): ###" >> $metadata
    oc get pods -A $SYSADM -o wide | grep -i $node >> $metadata
  #fi
done
