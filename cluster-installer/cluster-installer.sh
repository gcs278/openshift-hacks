#!/usr/bin/env bash
set -euo pipefail

function print_usage_exit() {
    echo "usage: $(basename $0) create <VERSION_DIR> {aws|gcp|azure|aws-sts} [MOD_SCRIPT]"
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

# Always remove the building file on exit
BUILDING_FILE=${CLUSTER_DIR}/building
function cleanup {
  rm -f ${BUILDING_FILE}
}
trap cleanup EXIT

echo $CLUSTER_DIR

AUTHS_JSON="$(jq ".auths" $HOME/.secrets/pull-secret.txt | jq -c .)"

#SDN_TYPE=OpenshiftSDN
SDN_TYPE=OVNKubernetes

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
  networkType: ${SDN_TYPE}
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
  platform:
    aws:
      type: t3a.xlarge
controlPlane:
  architecture: amd64
  hyperthreading: Enabled
  name: master
  platform:
    aws:
      type: t3a.xlarge
  replicas: 3
metadata:
  name: ${NAME}
networking:
  clusterNetwork:
  - cidr: 10.128.0.0/14
    hostPrefix: 23
  machineNetwork:
  - cidr: 10.0.0.0/16
  networkType: ${SDN_TYPE}
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
  networkType: ${SDN_TYPE}
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

function create_aws_sts_config {
    AWS_REGION=$(aws configure get region)
    AWS_ACCOUNT=$(aws sts get-caller-identity | awk '{print $1}')

    # Instructions: https://docs.openshift.com/container-platform/4.13/authentication/managing_cloud_provider_credentials/cco-mode-sts.html#sts-mode-installing_cco-mode-sts
    RELEASE_IMAGE=$($INSTALLER version | awk '/release image/ {print $3}')
    CCO_IMAGE=$(oc adm release info --image-for='cloud-credential-operator' $RELEASE_IMAGE -a ~/.secrets/pull-secret.txt)
    oc image extract $CCO_IMAGE --path="/usr/bin/ccoctl:${CLUSTER_DIR}" -a ~/.secrets/pull-secret.txt
    CCOCTL=${CLUSTER_DIR}/ccoctl
    chmod 775 ${CCOCTL}
    REGISTRY_AUTH_FILE=/home/gspence/.secrets/pull-secret.txt oc adm release extract --credentials-requests --cloud=aws --to=${CLUSTER_DIR}/credrequests --from=$RELEASE_IMAGE
    ${CCOCTL} aws create-all --name=${NAME} --region=${AWS_REGION} --credentials-requests-dir=${CLUSTER_DIR}/credrequests --output-dir=${CLUSTER_DIR}/sts
    # This was only required for 4.14.0-ec.4, but was fixed later for some reason
    #${CCOCTL} aws create-iam-roles --name=${NAME} --region=${AWS_REGION} --credentials-requests-dir=${CLUSTER_DIR}/credrequests --output-dir=${CLUSTER_DIR}/sts --identity-provider-arn=arn:aws:iam::${AWS_ACCOUNT}:oidc-provider/${NAME}-oidc.s3.${AWS_REGION}.amazonaws.com
    
    SSH_KEY=$(<$HOME/.ssh/id_rsa.pub)

    cat << EOF > ${CLUSTER_DIR}/install-config.yaml
apiVersion: v1
baseDomain: devcluster.openshift.com
credentialsMode: Manual
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
  networkType: ${SDN_TYPE}
  serviceNetwork:
  - 172.30.0.0/16
platform:
  aws:
    region: ${AWS_REGION}
publish: External
pullSecret: '{"auths": ${AUTHS_JSON}}'
sshKey: '${SSH_KEY}'
EOF
   
   cat ${CLUSTER_DIR}/install-config.yaml
   ${INSTALLER} create manifests --dir="${CLUSTER_DIR}"

   cp ${CLUSTER_DIR}/sts/manifests/* ${CLUSTER_DIR}/manifests
   cp -a ${CLUSTER_DIR}/sts/tls ${CLUSTER_DIR}/
}

function create() {
    if [ -d "$CLUSTER_DIR" ]; then
        echo "Error: ${CLUSTER_DIR} already exists"
        exit 1
    fi

    if ! podman login --authfile ~/.secrets/pull-secret.txt registry.ci.openshift.org <&-; then
      echo "ERROR: You are not logged into registry.ci.openshift.org. You must:"
      echo ""
      echo "    1. Visit https://console.redhat.com/openshift/install/pull-secret and download pull-secret"
      echo "    2. cp ~/Downloads/pull-secret to ~/.secrets/pull-secret.txt"
      echo "    3. Visit https://console-openshift-console.apps.ci.l2s4.p1.openshiftapps.com/"
      echo "    4. Log in -> Copy login command -> unset KUBECONFIG -> Use login command"
      echo "    5. oc registry login --to=/home/$USER/.secrets/pull-secret.txt"
      echo "    6. Test via:"
      echo "       podman login --authfile ~/.secrets/pull-secret.txt registry.ci.openshift.org"
      exit 1
    fi

    CLUSTER_ID=$(python3 -c "import uuid, sys;sys.stdout.write(str(uuid.uuid4()))")

    if [ "$PLATFORM" == "aws" ]; then
        mkdir "$CLUSTER_DIR"
        create_aws_config
    elif [ "$PLATFORM" == "aws-sts" ]; then
        mkdir "$CLUSTER_DIR"
        create_aws_sts_config
    elif [ "$PLATFORM" == "azure" ]; then
        mkdir "$CLUSTER_DIR"
        create_azure_config
    elif [ "$PLATFORM" == "gcp" ]; then
        mkdir "$CLUSTER_DIR"
        create_gcp_config
        export GOOGLE_APPLICATION_CREDENTIALS=~/.gcloud/ocp_installer_access_key.json
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
    if [[ -f $CLUSTER_DIR/install-config.yaml ]]; then
      cat $CLUSTER_DIR/install-config.yaml
    fi
    touch ${BUILDING_FILE}
    ${INSTALLER} create cluster --dir="$CLUSTER_DIR"
}

function delete() {
  if [[ -f ${CLUSTER_DIR}/metadata.json ]]; then 
    GOOGLE_APPLICATION_CREDENTIALS=~/.gcloud/ocp_installer_access_key.json \
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
