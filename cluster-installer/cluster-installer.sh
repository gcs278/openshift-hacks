#!/usr/bin/env bash
set -euo pipefail

function print_usage_exit() {
    echo "usage: $(basename $0) create <VERSION_DIR> {aws|gcp|azure} [MOD_SCRIPT]"
    echo "                      delete <CLUSTER_DIR>"
    echo "       e.g. $(basename $0) create 4.10.5 aws"
    exit 1
}

export PATH=$PWD:$PATH

WHAT="${1:-}"
if [[ "$WHAT" == "create" ]]; then
  VERSION_DIR="${2:-}"
  VERSION_DIR=$(basename $VERSION_DIR)
  PLATFORM="${3:-}"
  NAME="gspence-$(date +%Y-%m-%d-%H%M)"
  CLUSTER_DIR="${VERSION_DIR}/${PLATFORM}-${NAME}"
  MOD_SCRIPT="${4:-}"
  if [[ ! -z "$MOD_SCRIPT" ]] && [[ ! -f "$MOD_SCRIPT" ]]; then
    echo "ERROR: MOD_SCRIPT $MOD_SCRIPT is not a file"
    exit 1
  fi
elif [[ "$WHAT" == "delete" ]]; then
  CLUSTER_DIR="${2:-}"
  NAME=$(basename $CLUSTER_DIR)
  VERSION_DIR=$(dirname $CLUSTER_DIR)
  PLATFORM=$(echo $NAME | awk -F'-' '{print $1}')
  if [[ ! -d "${CLUSTER_DIR}" ]]; then
    echo "ERROR: ${CLUSTER_DIR} doesn't exist"
    exit 1
  fi
else
  print_usage_exit
fi

INSTALLER="${VERSION_DIR}/openshift-install"
if [[ ! -f "${INSTALLER}" ]]; then
  echo "ERROR: ${INSTALLER} doesn't exist"
  print_usage_exit
fi


if [ -z "$WHAT" ]; then print_usage_exit; fi
if [ -z "$NAME" ]; then print_usage_exit; fi
if [ -z "$CLUSTER_DIR" ]; then print_usage_exit; fi
if [ -z "$PLATFORM" ]; then print_usage_exit; fi


echo $CLUSTER_DIR

AUTHS_JSON="$(jq ".auths" $HOME/.secrets/pull-secret.txt | jq -c .)"

function create_gcp_config {
    SSH_KEY=$(<$HOME/.ssh/id_rsa.pub)
    # compute:
    # - name: worker
    #   replicas: 3
    # controlPlane:
    #   name: master
    #   replicas: 3

    cat << EOF > ${CLUSTER_DIR}/install-config.yaml
apiVersion: v1
baseDomain: gcp.devcluster.openshift.com
metadata:
  name: ${NAME}
networking:
  clusterNetwork:
  - cidr: 10.128.0.0/14
    hostPrefix: 23
  machineCIDR: 10.0.0.0/16
  networkType: OpenShiftSDN
  serviceNetwork:
  - 172.30.0.0/16
platform:
  gcp:
    region: us-east1
    projectID: openshift-gce-devel
pullSecret: '{"auths": ${AUTHS_JSON}}'
sshKey: '${SSH_KEY}'
EOF
}

function create_aws_config {
    AWS_REGION=$(aws configure get region)
    SSH_KEY=$(<$HOME/.ssh/id_rsa.pub)

    cat << EOF > ${CLUSTER_DIR}/install-config.yaml
apiVersion: v1
baseDomain: devcluster.openshift.com
compute:
- architecture: amd64
  hyperthreading: Enabled
  name: worker
  replicas: 3
controlPlane:
  architecture: amd64
  hyperthreading: Enabled
  name: master
  platform: {}
  replicas: 3
metadata:
  name: ${NAME}
networking:
  clusterNetwork:
  - cidr: 10.128.0.0/14
    hostPrefix: 23
  machineNetwork:
  - cidr: 10.0.0.0/16
  networkType: OpenShiftSDN
  serviceNetwork:
  - 172.30.0.0/16
platform:
  aws:
    region: ${AWS_REGION}
publish: External
pullSecret: '{"auths": ${AUTHS_JSON}}'
sshKey: '${SSH_KEY}'
EOF
}

function create_azure_config {
    local sp_file="${HOME}/.azure/osServicePrincipal.json"
    if [ ! -f $sp_file ]; then
        if ! az account show &> /dev/null; then
          echo "ERROR: You must log into azure cloud via \"az login\""
          exit 1
        fi
        local SUB_ID="$(az account show | jq -r '.id')"
        local SP=$(az ad sp create-for-rbac --role="Owner" --scopes="/subscriptions/${SUB_ID}" --name "${NAME}-installer")
        echo "created new service principal:"
        echo "$SP"
        jq --arg SUB_ID "$SUB_ID" '{subscriptionId:$SUB_ID,clientId:.appId, clientSecret:.password,tenantId:.tenant}' <<< $SP >$sp_file
        echo "created new credentials at $sp_file"
    fi
    local AZURE_REGION="centralus"
    # TODO: jq -r '.auths | {"auths": .}' $HOME/.secrets/openshift-pull-secret.json
    local SSH_KEY=$(<$HOME/.ssh/id_rsa.pub)

    cat << EOF > ${CLUSTER_DIR}/install-config.yaml
apiVersion: v1
baseDomain: networkedge.azure.devcluster.openshift.com
metadata:
  name: ${NAME}
compute:
- hyperthreading: Enabled
  name: worker
  replicas: 3
controlPlane:
  hyperthreading: Enabled
  name: master
  replicas: 3
networking:
  clusterNetwork:
  - cidr: 10.128.0.0/14
    hostPrefix: 23
  machineCIDR: 10.0.0.0/16
  networkType: OpenShiftSDN
  serviceNetwork:
  - 172.30.0.0/16
platform:
  azure:
    baseDomainResourceGroupName: os4-common
    region: ${AZURE_REGION}
pullSecret: '{"auths": ${AUTHS_JSON}}'
sshKey: '${SSH_KEY}'
EOF
    #export ARM_CLIENT_ID="$(jq -r '.clientId' $sp_file)"
    #export ARM_CLIENT_SECRET="$(jq -r '.clientSecret' $sp_file)"
    #export ARM_SUBSCRIPTION_ID="$(jq -r '.subscriptionId' $sp_file)"
    #export ARM_TENANT_ID="$(jq -r '.tenantId' $sp_file)"
}

function create() {
    if [ -d "$CLUSTER_DIR" ]; then
        echo "Error: ${CLUSTER_DIR} already exists"
        exit 1
    fi

    CLUSTER_ID=$(python3 -c "import uuid, sys;sys.stdout.write(str(uuid.uuid4()))")

    if [ "$PLATFORM" == "aws" ]; then
        mkdir "$CLUSTER_DIR"
        create_aws_config
    elif [ "$PLATFORM" == "azure" ]; then
        mkdir "$CLUSTER_DIR"
        create_azure_config
    elif [ "$PLATFORM" == "gcp" ]; then
        mkdir "$CLUSTER_DIR"
        create_gcp_config
        export GOOGLE_APPLICATION_CREDENTIALS=~/src/github.com/openshift/shared-secrets/gce/aos-serviceaccount.json
    else
        echo "unrecognized platform '$PLATFORM'"
        exit 1
    fi
    if [ "$WHAT" == "config" ]; then
       echo "wrote install config to $CLUSTER_DIR"
       exit 0
    fi

    if [[ "$MOD_SCRIPT" != "" ]]; then
      bash $MOD_SCRIPT ${CLUSTER_DIR}/install-config.yaml
      if [[ $? -ne 0 ]]; then
        echo "ERROR: The mod_script $MOD_SCRIPT failed"
	exit 1
      fi
    fi
    cat $CLUSTER_DIR/install-config.yaml
    ${INSTALLER} create cluster --dir="$CLUSTER_DIR"
}

function delete() {
  if [[ -f ${CLUSTER_DIR}/metadata.json ]]; then 
    GOOGLE_APPLICATION_CREDENTIALS=~/src/github.com/openshift/shared-secrets/gce/aos-serviceaccount.json \
      ${INSTALLER} destroy cluster --dir="$CLUSTER_DIR"
  else
    echo "Not a real cluster, just deleting dir"
  fi

  rm -rf "$CLUSTER_DIR"
}

export AWS_PROFILE="openshift-dev"

if [ "$WHAT" == "create" ]; then
    create
elif [ "$WHAT" == "delete" ]; then
    delete
else
    print_usage_exit
fi
