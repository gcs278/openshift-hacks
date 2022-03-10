#!/bin/bash

set -euo pipefail

if [[ "$1" == "" ]]; then
  echo "ERROR: You must provide an image name"
  exit 1
fi

IMAGE_NAME="$1"

if [[ -z "${GIT_BRANCH+1}" ]]
then
    GIT_BRANCH="$(git symbolic-ref --short HEAD)"
fi

if [[ -z "${GIT_URL+1}" ]]
then
    if ! GIT_REMOTE="$(git config "branch.${GIT_BRANCH}.pushDefault")" || [[ "$GIT_REMOTE" = '.' ]]; then
      if ! GIT_REMOTE="$(git config 'remote.pushDefault')"; then
        GIT_REMOTE="origin"
      fi
    fi
    GIT_URL=$(git config "remote.${GIT_REMOTE}.url")
fi

if [[ "$GIT_URL" =~ ^git@ ]]
then
    # Convert git@host:user/repo to https://host/user/repo.
    GIT_URL="${GIT_URL/://}"
    GIT_URL="https://${GIT_URL#git@}"
fi

oc process -f "$(dirname "$0")/buildconfig.yaml" \
   -p "GIT_URL=$GIT_URL" \
   -p "GIT_BRANCH=$GIT_BRANCH" \
   -p "IMAGE_NAME=$IMAGE_NAME" \
    | oc apply -f -
