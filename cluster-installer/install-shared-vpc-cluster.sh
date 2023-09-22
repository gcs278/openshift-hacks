#!/bin/bash

set -e

PROFILE_A="openshift-shared-vpc"
PROFILE_B="openshift-dev"
REGION_A="us-east-2"
REGION_B="us-east-2"

USER_ARN_B=$(aws --profile $PROFILE_B --region $REGION_B sts get-caller-identity --output json | jq -r '.Arn')

USERNAME="gspence"
VPC_STACK_NAME="${USERNAME}-sharedvpc1"
VPC_TPL_PATH=/tmp/01_vpc.yaml
VPC_TPL=file://${VPC_TPL_PATH}
POLICY_NAME=${USERNAME}-pol1
ROLE_NAME=${USERNAME}-rol1

# PHZ Variables
CLUSTER_BASE_DOMAIN=devcluster.openshift.com # <- Public zone in cluster creator's account (Account B)
CLUSTER_NAME="${USERNAME}-demovpc2"
PRIVATE_HOSTED_ZONE_NAME=${CLUSTER_NAME}.${CLUSTER_BASE_DOMAIN}

function print_usage_exit() {
    echo "usage: $(basename $0) [create|delete]"
    exit 1
}

function create() {
  # Download VPC Template from Github to /tmp
  if [[ ! -f $VPC_TPL_PATH ]]; then
    wget -P /tmp https://raw.githubusercontent.com/openshift/installer/master/upi/aws/cloudformation/01_vpc.yaml
  fi

  if ! aws --profile $PROFILE_A --region $REGION_A cloudformation describe-stacks --stack-name $VPC_STACK_NAME > /dev/null; then
    echo "Creating stack $VPC_STACK_NAME..."
    aws --profile $PROFILE_A --region $REGION_A cloudformation create-stack --template-body ${VPC_TPL} --stack-name $VPC_STACK_NAME
  else
    echo "Stack $VPC_STACK_NAME already exists"
  fi


  # Wait for stack to finish creation
  while [[ $(aws --profile $PROFILE_A --region $REGION_A cloudformation describe-stacks --stack-name $VPC_STACK_NAME --output json | jq -r '.Stacks[].StackStatus') != "CREATE_COMPLETE" ]]; do
    echo "Waiting for stack $VPC_STACK_NAME status to be CREATE_COMPLETE..."
    sleep 5
  done

  VPC_ID=$(aws --profile $PROFILE_A --region $REGION_A cloudformation describe-stacks --stack-name ${VPC_STACK_NAME} --output json | jq -r '.Stacks[].Outputs[] | select(.OutputKey == "VpcId").OutputValue')
  ALL_SUBNET_IDS=$(aws --profile $PROFILE_A --region $REGION_A cloudformation describe-stacks --stack-name ${VPC_STACK_NAME} --output json | jq -r '.Stacks[].Outputs[] | select(.OutputKey | endswith("SubnetIds")).OutputValue')
  ALL_SUBNET_ARNS=$(aws --profile $PROFILE_A --region $REGION_A ec2 describe-subnets --subnet-ids ${ALL_SUBNET_IDS} --output json | jq -r '.Subnets[].SubnetArn')
  
  # Make resource share named by VPC, so it's deterministic since it takes 2 hours to delete and you can't recreate one with the same name
  # if the stack was recreated
  RESOURCE_SHARE_NAME=${USERNAME}-${VPC_ID}

  # Create Resource shares
  if [[ $(aws --profile $PROFILE_A --region $REGION_A ram get-resource-shares --resource-owner SELF --name $RESOURCE_SHARE_NAME) == "" ]]; then
    echo "Creating resource share $RESOURCE_SHARE_NAME..."
    PROFILE_B_ACCOUNT_NUM=$(aws sts get-caller-identity --query Account --output text --profile $PROFILE_B)
    aws --profile $PROFILE_A --region $REGION_A ram create-resource-share --name ${RESOURCE_SHARE_NAME} --resource-arns ${ALL_SUBNET_ARNS} --principals $PROFILE_B_ACCOUNT_NUM
  else
    echo "Resource share $RESOURCE_SHARE_NAME arleady exists...updating"
  fi

  # Create Private Hosted Zone (PHZ)
  if ! aws --profile $PROFILE_A --region $REGION_A route53 list-hosted-zones | grep -q ${PRIVATE_HOSTED_ZONE_NAME}; then
    echo "Creating Hosted Zone $PRIVATE_HOSTED_ZONE_NAME..."
    CALLER_REFERENCE_STR="$PRIVATE_HOSTED_ZONE_NAME-$(date +%s)"
    HOSTED_ZONE_CREATION=$(aws --profile $PROFILE_A --region $REGION_A route53 create-hosted-zone --name "${PRIVATE_HOSTED_ZONE_NAME}" --vpc VPCRegion="${REGION_A}",VPCId="${VPC_ID}" --caller-reference "${CALLER_REFERENCE_STR}" --output json)
    HOSTED_ZONE_ID="$(echo "${HOSTED_ZONE_CREATION}" | jq -r '.HostedZone.Id' | awk -F / '{printf $3}')"
    CHANGE_ID="$(echo "${HOSTED_ZONE_CREATION}" | jq -r '.ChangeInfo.Id' | awk -F / '{printf $3}')"
    while [[ $(aws --profile $PROFILE_A --region $REGION_A route53 get-change --id $CHANGE_ID --output json | jq -r '.ChangeInfo.Status') != "INSYNC" ]]; do
      echo "Waiting for Hosted Zone for $PRIVATE_HOSTED_ZONE_NAME to go INSYNC"
      sleep 3
    done
  else
    echo "Hosted Zone already exists"
    HOSTED_ZONE_ID=$(aws --profile $PROFILE_A --region $REGION_A route53 list-hosted-zones --output json | jq -r '.HostedZones[] | select(.Name=="'${PRIVATE_HOSTED_ZONE_NAME}'.").Id' | awk -F / '{printf $3}')
  fi

  # Create IAM policy
  if [[ $(aws --profile $PROFILE_A --region $REGION_A iam list-policies --output json | jq -r '.Policies[] | select(.PolicyName=="'${POLICY_NAME}'").Arn') == "" ]]; then
    echo "Creating Policy $POLICY_NAME..."
    POLICY_DOC=$(mktemp)
    POLICY_OUT=$(mktemp)
    cat <<EOF> $POLICY_DOC
{
   "Version": "2012-10-17",
   "Statement": [
       {
           "Effect": "Allow",
           "Action": [
	       "elasticloadbalancing:DescribeLoadBalancers",
               "route53:ListHostedZones",
               "route53:ListTagsForResources",
               "route53:ChangeResourceRecordSets",
               "tag:GetResources",
               "sts:AssumeRole"
           ],
           "Resource": [
               "*"
           ]
       }
   ]
}
EOF
    
    cmd="aws --profile $PROFILE_A --region $REGION_A iam create-policy --policy-name ${POLICY_NAME} --policy-document '$(cat $POLICY_DOC | jq -c)' --output json > ${POLICY_OUT}"
    eval "${cmd}"
    POLICY_ARN=$(cat ${POLICY_OUT} | jq -r '.Policy.Arn')
  else
    echo "Policy $POLICY_NAME already exists"
    POLICY_ARN=$(aws --profile $PROFILE_A --region $REGION_A iam list-policies --output json | jq -r '.Policies[] | select(.PolicyName=="'${POLICY_NAME}'").Arn')
  fi

  # Create IAM role
  if [[ $(aws --profile $PROFILE_A --region $REGION_A iam list-roles --output json | jq -r '.Roles[] | select(.RoleName=="'${ROLE_NAME}'").Arn') == "" ]]; then
    echo "Creating Role $ROLE_NAME..."
    ASSUME_ROLE_POLICY_DOC=$(mktemp)
    CLUSTER_CREATOR_USER_ARN=$(aws --profile $PROFILE_B --region $REGION_B sts get-caller-identity --output json | jq -r '.Arn')
    cat <<EOF> $ASSUME_ROLE_POLICY_DOC
{
   "Version": "2012-10-17",
   "Statement": [
       {
           "Effect": "Allow",
           "Principal": {
               "AWS": "${CLUSTER_CREATOR_USER_ARN}"
           },
           "Action": "sts:AssumeRole",
           "Condition": {}
       }
   ]
}
EOF
    aws --profile $PROFILE_A --region $REGION_A iam create-role --role-name ${ROLE_NAME} --assume-role-policy-document file://${ASSUME_ROLE_POLICY_DOC}
  else
    echo "Role $ROLE_NAME already exists"
  fi

  # Attach our created policy to our created role
  if ! aws --profile $PROFILE_A --region $REGION_A iam list-attached-role-policies --role-name $ROLE_NAME | grep -i "$POLICY_NAME"; then
    echo "Attaching policy $POLICY_NAME to role $ROLE_NAME"
    # Attach policy to role
    aws --profile $PROFILE_A --region $REGION_A iam attach-role-policy --role-name ${ROLE_NAME} --policy-arn ${POLICY_ARN}
  else
    echo "Policy $POLICY_NAME is already attached to role $ROLE_NAME"
  fi

  # Attach AmazonRoute53FullAccess policy to our created role
  if ! aws --profile $PROFILE_A --region $REGION_A iam list-attached-role-policies --role-name $ROLE_NAME | grep -i "AmazonRoute53FullAccess"; then
    echo "Attaching policy AmazonRoute53FullAccess to role $ROLE_NAME"
    # Attach policy to role
    aws --profile $PROFILE_A --region $REGION_A iam attach-role-policy --role-name ${ROLE_NAME} --policy-arn 'arn:aws:iam::aws:policy/AmazonRoute53FullAccess'
  else
    echo "Policy AmazonRoute53FullAccess is already attached to role $ROLE_NAME"
  fi
  
  # Attach ResourceGroupsandTagEditorFullAccess policy to our created role
  if ! aws --profile $PROFILE_A --region $REGION_A iam list-attached-role-policies --role-name $ROLE_NAME | grep -i "ResourceGroupsandTagEditorFullAccess"; then
    echo "Attaching policy AmazonRoute53FullAccess to role $ROLE_NAME"
    # Attach policy to role
    aws --profile $PROFILE_A --region $REGION_A iam attach-role-policy --role-name ${ROLE_NAME} --policy-arn 'arn:aws:iam::aws:policy/ResourceGroupsandTagEditorFullAccess'
  else
    echo "Policy ResourceGroupsandTagEditorFullAccess is already attached to role $ROLE_NAME"
  fi

  ROLE_ARN=$(aws --profile $PROFILE_A --region $REGION_A iam get-role --role-name ${ROLE_NAME} --output json | jq -r '.Role.Arn')
  echo "Account $PROFILE_A has been successfully configured for Account $PROFILE_B to use shared VPC"
  echo
  echo "Place these in the install-config of account b ($PROFILE_B)"
  cat << EOF
platform:
  aws:
    region: $REGION_A
    hostedZone: $HOSTED_ZONE_ID
    hostedZoneRole: $ROLE_ARN
    subnets:
EOF
  for i in $ALL_SUBNET_IDS; do
    echo "    - $i"
  done
}

function delete() {
  echo "Deleting stack ${VPC_STACK_NAME}..."
  if aws --profile $PROFILE_A --region $REGION_A cloudformation describe-stacks --stack-name $VPC_STACK_NAME > /dev/null; then
    aws --profile $PROFILE_A --region $REGION_A cloudformation delete-stack --stack-name $VPC_STACK_NAME
  else
    echo "Stack already deleted"
  fi

  echo "Deleting all resource-shares (NOTE: takes 2 hours to be removed completely)"
  for i in $(aws --profile $PROFILE_A --region $REGION_A ram get-resource-shares --resource-owner SELF --output json | jq -r '.resourceShares[] | select(.name | startswith("'$USERNAME'"))' | jq -r '.resourceShareArn'); do
    aws --profile $PROFILE_A --region $REGION_A ram delete-resource-share --resource-share-arn $i
  done

  echo "Deleting private hosted zone ${PRIVATE_HOSTED_ZONE_NAME}..."
  if aws --profile $PROFILE_A --region $REGION_A route53 list-hosted-zones | grep -q ${PRIVATE_HOSTED_ZONE_NAME}; then
    HOSTED_ZONE_ID=$(aws --profile $PROFILE_A --region $REGION_A route53 list-hosted-zones --output json | jq -r '.HostedZones[] | select(.Name=="'${PRIVATE_HOSTED_ZONE_NAME}'.").Id' | awk -F / '{printf $3}')
    aws --profile $PROFILE_A --region $REGION_A route53 delete-hosted-zone --id $HOSTED_ZONE_ID
  else
    echo "Private hosted zone already deleted"
  fi
  
  echo "Detaching policies from role ${ROLE_NAME}..."
  for i in $(aws --profile $PROFILE_A --region $REGION_A iam list-attached-role-policies --role-name ${ROLE_NAME} --output json | jq -r '.AttachedPolicies[].PolicyArn'); do
    echo "Detaching $i from $ROLE_NAME"
    aws --profile $PROFILE_A --region $REGION_A iam detach-role-policy --role-name $ROLE_NAME --policy-arn $i
  done

  echo "Deleting IAM Role ${ROLE_NAME}..."
  if [[ $(aws --profile $PROFILE_A --region $REGION_A iam list-roles --output json | jq -r '.Roles[] | select(.RoleName=="'${ROLE_NAME}'").Arn') != "" ]]; then
    aws --profile $PROFILE_A --region $REGION_A iam delete-role --role-name ${ROLE_NAME}
  else
    echo "IAM Role already deleted"
  fi

  echo "Deleting IAM Policy ${POLICY_NAME}..."
  POLICY_ARN=$(aws --profile $PROFILE_A --region $REGION_A iam list-policies --output json | jq -r '.Policies[] | select(.PolicyName=="'${POLICY_NAME}'").Arn')
  if [[ "$POLICY_ARN" != "" ]]; then
    aws --profile $PROFILE_A --region $REGION_A iam delete-policy --policy-arn $POLICY_ARN
  else
    echo "IAM Policy already deleted"
  fi
  
  echo "Successfully deleted all Shared VPC objects for $USERNAME"
}

WHAT="${1:-}"
if [[ "$WHAT" == "create" ]]; then
  create
elif [[ "$WHAT" == "delete" ]]; then
  delete
else
  print_usage_exit
fi

