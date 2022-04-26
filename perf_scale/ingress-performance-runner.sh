#!/bin/bash

source ./env.sh
alias python=python3

trap "pkill -P $$" EXIT

LOG_DIR=./logs
RUNNER_LOG=${LOG_DIR}/runner-$(date +"%Y_%m_%d_%I_%M_%p")

function log() {
  echo "$@"
  echo "$@" >> $RUNNER_LOG
}

function run() {
  test_name=$1
  test_envrc=$2
  baseline=$3
  if [[ "$1" == "" ]]; then
    log "ERROR: You must provide a test name"
    exit 1
  fi
  if [[ ! -f "$2" ]]; then
    log "ERROR: $2 is not a file that we can source"
    exit 1
  fi
  # Optional
  export BASELINE_UUID=${baseline}
  # Unset because these may not be specified
  unset HAPROXY_IMAGE
  unset INGRESS_OPERATOR_IMAGE

  TEST_LOG_DIR=${LOG_DIR}/${test_name}-$(date +%Y-%m-%d)
  while [[ -d ${TEST_LOG_DIR} ]]; do
    TEST_LOG_DIR="${TEST_LOG_DIR}-1"
  done
  source ${test_envrc}
  if [[ $? -ne 0 ]]; then
    log "ERROR: Failed to source ${test_envrc}"
    exit 1
  fi
  mkdir -p $TEST_LOG_DIR
  LIMIT_ATTEMPTS=3
  ATTEMPT=1
  while [[ ! -f ${COMPARISON_OUTPUT} ]]; do
    TEST_LOG=${TEST_LOG_DIR}/log-${ATTEMPT}
    start=$(date +%s)
    log "Starting test attempt #${ATTEMPT} at $(date)"
    ./ingress-performance.sh &> $TEST_LOG
    end=$(date +%s)
    runtime=$((end-start))
    hours=$((runtime / 3600)); minutes=$(( (runtime % 3600) / 60 )); seconds=$(( (runtime % 3600) % 60 ));
    log "Test Exitted. Runtime: $hours:$minutes:$seconds (hh:mm:ss)"
    if [[ ! -f ${COMPARISON_OUTPUT} ]]; then
      log "ERROR: Test attempt #${ATTEMPT} failed. ${COMPARISON_OUTPUT} does not exist. Trying again."
      ATTEMPT=$((ATTEMPT+1))
      if [[ ${ATTEMPT} -gt ${LIMIT_ATTEMPTS} ]]; then
        log "ERROR: Giving up after ${LIMIT_ATTEMPTS} failed attempts"
	exit 1
      fi
    else
      log "Test attempt #${ATTEMPT} success!"
      log "Moving ${COMPARISON_OUTPUT} to $TEST_LOG_DIR"
      mv ${COMPARISON_OUTPUT} $TEST_LOG_DIR
      return
    fi
  done
}

if [ -t 1 ] ; then
  log "ERROR: You need to run this script with nohup for stablity"
  exit 1 
fi

if [[ -f ${COMPARISON_OUTPUT} ]]; then
  log "ERROR: Refusing to start because ${COMPARISON_OUTPUT} already exists"
  exit 1
fi

#run "baseline" ./envrc-replicas1
run "replicas1-weights-random" ./envrc-replicas1-weights-random "0f7354c4-1c7e-49a4-a7f3-fa196acfbc8b"
run "replicas1-weights" ./envrc-replicas1-weights "0f7354c4-1c7e-49a4-a7f3-fa196acfbc8b"
