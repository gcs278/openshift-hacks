#!/bin/bash

trap "pkill -P $$" EXIT

# Manage Python Environment
# Cleaner and manages version of python
python3 -m venv pyenv
source pyenv/bin/activate

PS_DIR=e2e-benchmarking
REPO=https://github.com/cloud-bulldozer/${PS_DIR}
if [[ ! -d "$PS_DIR" ]]; then
  git clone $REPO
else
  cd $PS_DIR
  git pull $REPO
  if [[ $? -ne 0 ]]; then
    echo "ERROR: Failed to update $PS_DIR"
    exit 1
  fi
  cd -
fi

LOG_DIR=./results
RUNNER_LOG_DIR=${LOG_DIR}/runner-logs/
RUNNER_LOG=${RUNNER_LOG_DIR}/runner-$(date +"%Y_%m_%d_%I_%M_%p")
mkdir -p $LOG_DIR $RUNNER_LOG_DIR
SECRETS=./secrets.env
ROUTER_PERF_DIR=${PS_DIR}/workloads/router-perf-v2/

function log() {
  echo "$(date -u): ${@}"
  echo "$(date -u): ${@}" >> ${RUNNER_LOG}
}

function run() {
  test_envrc=$1
  baseline=$2
  if [[ ! -f "$test_envrc" ]]; then
    log "ERROR: $test_envrc is not a file that we can source"
    exit 1
  fi
  test_name=$(basename $test_envrc)
  test_name=${test_name%.env}

  # Optional
  export BASELINE_UUID=${baseline}
  # Unset because these may not be specified
  unset HAPROXY_IMAGE
  unset INGRESS_OPERATOR_IMAGE

  TEST_LOG_DIR=${LOG_DIR}/${test_name}-$(date +%Y-%m-%d)
  TEST_LOG_DIR_ORIG=${TEST_LOG_DIR}
  TRY=1
  while [[ -d ${TEST_LOG_DIR} ]]; do
    TEST_LOG_DIR="${TEST_LOG_DIR_ORIG}_${TRY}"
    TRY=$((TRY+1))
  done
  source ${SECRETS}
  source ${test_envrc}
  if [[ $? -ne 0 ]]; then
    log "ERROR: Failed to source ${test_envrc}"
    exit 1
  fi
  if [[ "$BASELINE_UUID" == "" ]]; then
    export COMPARISON_OUTPUT_CFG=${TEST_LOG_DIR}/${test_name}-perfomance.csv
  else
    export COMPARISON_OUTPUT_CFG=${TEST_LOG_DIR}/${test_name}-comparison.csv
  fi
  mkdir -p $TEST_LOG_DIR
  LIMIT_ATTEMPTS=5
  ATTEMPT=1
  while [[ ! -f ${COMPARISON_OUTPUT_CFG} ]]; do
    TEST_LOG=${TEST_LOG_DIR}/log-${ATTEMPT}
    cd ${ROUTER_PERF_DIR}
    start=$(date +%s)
    log "Starting test ${test_name} attempt #${ATTEMPT}"
    log "Log is ${TEST_LOG}"
    ./ingress-performance.sh &> $TEST_LOG
    end=$(date +%s)
    cd -
    runtime=$((end-start))
    hours=$((runtime / 3600)); minutes=$(( (runtime % 3600) / 60 )); seconds=$(( (runtime % 3600) % 60 ));
    log "Test Exitted. Runtime: $hours:$minutes:$seconds (hh:mm:ss)"
    if [[ ! -f ${COMPARISON_OUTPUT_CFG} ]]; then
      log "ERROR: Test attempt #${ATTEMPT} failed. ${COMPARISON_OUTPUT_CFG} does not exist. Trying again."
      ATTEMPT=$((ATTEMPT+1))
      if [[ ${ATTEMPT} -gt ${LIMIT_ATTEMPTS} ]]; then
        log "ERROR: Giving up after ${LIMIT_ATTEMPTS} failed attempts"
	return
      fi
      log "Sleeping for 2 minutes to try to wait for things to settle down"
      sleep 120
    else
      log "Test attempt #${ATTEMPT} success!"
      mv ${ROUTER_PERF_DIR}/results.csv ${TEST_LOG_DIR}/${test_name}-results.csv
      echo "Errors: $(grep -v ",$" ${TEST_LOG_DIR}/${test_name}-results.csv | wc -l)" > ${TEST_LOG_DIR}/${test_name}-errors
      echo "Total Requests: $(cat ${TEST_LOG_DIR}/${test_name}-results.csv | wc -l)" >> ${TEST_LOG_DIR}/${test_name}-errors
      return
    fi
  done
}

# Recommend to run with nohup
if [ -t 1 ] ; then
  echo "It is HIGHLY recommend you run this script with nohup"
  echo "nohup $0 &"
  read -p "Are you sure you want to continue [y/N] " -r
  if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    exit 1
  fi
fi

if [[ ! -f ${SECRETS} ]]; then
  log "ERROR: The secrets file ${SECRETS} doesn't exist!"
  exit 1
fi

done=false
num=1
declare -A env_files
#while [[ "$done" == "false" ]]; do
#  read -e -p "ENV File for test #${num}: " file
#  if [[ ! -f "${file}" ]]; then
#    log "ERROR: ${file} is not a file"
#    continue
#  fi
#  read -e -p "UUID For Comparison (leave blank if none): " uuid
#  env_files[${file}]="${uuid}"
#  num=$((num+1))
#  read -p "Do you have more tests? [y/N] " -r
#  if [[ ! $REPLY =~ ^[Yy]$ ]]; then
#    done="true"
#  fi
#done
#

#for env_file in "${!env_files[@]}"; do
#  run "$env_file" "${env_files[$env_file]}"
#done

#run ./tests/replicas1-baseline.env
# Turn off probe tuning
#cp -f ./ingress-performance.sh.prob ./ingress-performance.sh
run ./tests/NE-709/replicas1-weights.env "456a8413-4d43-4ba3-9d42-fb4605ee0ee8"
run ./tests/NE-709/replicas1-weights-random.env "456a8413-4d43-4ba3-9d42-fb4605ee0ee8"
