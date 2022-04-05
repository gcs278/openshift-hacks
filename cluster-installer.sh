#!/usr/bin/env bash
set -euo pipefail

function print_usage_exit() {
    echo "usage: clusterctl <create|delete> <platform> <name>"
    exit 1
}

export PATH=$PWD:$PATH

WHAT="${1:-}"
PLATFORM="${2:-}"
if [[ "$WHAT" == "create" ]]; then
  NAME="${3:-gspence-$(date +%Y-%m-%d-%H%M)}"
elif [[ "$WHAT" == "delete" ]]; then
  NAME="${3:-}"
else
  print_usage_exit
fi

if [ -z "$WHAT" ]; then print_usage_exit; fi
if [ -z "$NAME" ]; then print_usage_exit; fi
if [ -z "$PLATFORM" ]; then print_usage_exit; fi

# If specified a path, then let's assume they wanted to reference a dir
if [[ -d "${NAME}" ]]; then
  CLUSTER_DIR="${NAME}"
  NAME=$(basename $NAME)
else
  CLUSTER_DIR="$PWD/${PLATFORM}-${NAME}"
fi

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
        if [ "$WHAT" == "config" ]; then
            echo "wrote install config to $CLUSTER_DIR"
            exit 0
        fi
        set -x
        ./openshift-install create cluster --dir="$CLUSTER_DIR"
    elif [ "$PLATFORM" == "azure" ]; then
        mkdir "$CLUSTER_DIR"
        create_azure_config
        if [ "$WHAT" == "config" ]; then
            echo "wrote install config to $CLUSTER_DIR"
            exit 0
        fi
        ./openshift-install create cluster --dir="$CLUSTER_DIR"
    elif [ "$PLATFORM" == "gcp" ]; then
        mkdir "$CLUSTER_DIR"
        create_gcp_config
        if [ "$WHAT" == "config" ]; then
            echo "wrote install config to $CLUSTER_DIR"
            exit 0
        fi
        GOOGLE_APPLICATION_CREDENTIALS=~/src/github.com/openshift/shared-secrets/gce/aos-serviceaccount.json \
           ./openshift-install create cluster --dir="$CLUSTER_DIR"
    else
        echo "unrecognized platform '$PLATFORM'"
        exit 1
    fi

    cat $CLUSTER_DIR/install-config.yaml
}

function delete() {
  GOOGLE_APPLICATION_CREDENTIALS=~/src/github.com/openshift/shared-secrets/gce/aos-serviceaccount.json \
    ./openshift-install destroy cluster --dir="$CLUSTER_DIR"

  rm -rf "$CLUSTER_DIR"
}

if [ "$WHAT" == "create" ]; then
    create
elif [ "$WHAT" == "delete" ]; then
    delete
else
    print_usage_exit
fi
