#!/usr/bin/env bash
#      Copyright (c) IBM Corporation.
#      Copyright (c) Microsoft Corporation.
################################################
# This script is invoked by a human who:
# - has done az login.
# - can create repository secrets in the github repo from which this file was cloned.
# - has the gh client >= 2.0.0 installed.
#
# This script initializes the repo from which this file was cloned
# with the necessary secrets to run the workflows.
# 
# This script should be invoked in the root directory of the github repo that was cloned, e.g.:
# ```
# cd <path-to-local-clone-of-the-github-repo>
# ./.github/workflows/setup-credentials.sh
# ``` 
#
# Script design taken from https://github.com/microsoft/NubesGen.
#
################################################

################################################
# Set environment variables - the main variables you might want to configure.
#
# Three letters to disambiguate names
DISAMBIG_PREFIX=
# User name for preceding GitHub account
USER_NAME=
# Owner/reponame, e.g., <USER_NAME>/azure.liberty.aks
OWNER_REPONAME=
# Client ID for an Azure AD application registered in the Partner Center
CLIENT_ID=
# Secret value of the Azure AD application registered in the Partner Center
SECRET_VALUE=
# Tenant ID of the Azure AD application registered in the Partner Center
TENANT_ID=
# Optional: Web hook for Microsoft Teams channel
MSTEAMS_WEBHOOK=

# End set environment variables
################################################


set -Eeuo pipefail
trap cleanup SIGINT SIGTERM ERR EXIT

cleanup() {
  trap - SIGINT SIGTERM ERR EXIT
  # script cleanup here
}

setup_colors() {
  if [[ -t 2 ]] && [[ -z "${NO_COLOR-}" ]] && [[ "${TERM-}" != "dumb" ]]; then
    NOFORMAT='\033[0m' RED='\033[0;31m' GREEN='\033[0;32m' ORANGE='\033[0;33m' BLUE='\033[0;34m' PURPLE='\033[0;35m' CYAN='\033[0;36m' YELLOW='\033[1;33m'
  else
    NOFORMAT='' RED='' GREEN='' ORANGE='' BLUE='' PURPLE='' CYAN='' YELLOW=''
  fi
}

msg() {
  echo >&2 -e "${1-}"
}

setup_colors

read -r -p "Enter a disambiguation prefix (try initials with a sequence number, such as ejb01): " DISAMBIG_PREFIX

if [ "$DISAMBIG_PREFIX" == '' ] ; then
    msg "${RED}You must enter a disambiguation prefix."
    exit 1;
fi

DISAMBIG_PREFIX=${DISAMBIG_PREFIX}`date +%m%d`

# get USER_NAME if not set at the beginning of this file
if [ "$USER_NAME" == '' ] ; then
    read -r -p "Enter user name of GitHub account: " USER_NAME
fi

# get OWNER_REPONAME if not set at the beginning of this file
if [ "$OWNER_REPONAME" == '' ] ; then
    read -r -p "Enter owner/reponame (blank for upsteam of current fork): " OWNER_REPONAME
fi

if [ -z "${OWNER_REPONAME}" ] ; then
    GH_FLAGS=""
else
    GH_FLAGS="--repo ${OWNER_REPONAME}"
fi

# get CLIENT_ID if not set at the beginning of this file
if [ "$CLIENT_ID" == '' ] ; then
    read -r -p "Enter client ID for an Azure AD application registered in the Partner Center: " CLIENT_ID
fi

# get SECRET_VALUE if not set at the beginning of this file
if [ "$SECRET_VALUE" == '' ] ; then
    read -r -p "Enter secret value for the Azure AD application registered in the Partner Center: " SECRET_VALUE
fi

# get TENANT_ID if not set at the beginning of this file
if [ "$TENANT_ID" == '' ] ; then
    read -r -p "Enter tenant ID for the Azure AD application registered in the Partner Center: " TENANT_ID
fi

# Optional: get MSTEAMS_WEBHOOK if not set at the beginning of this file
if [ "$MSTEAMS_WEBHOOK" == '' ] ; then
    read -r -p "[Optional] Enter Web hook for Microsoft Teams channel, or press 'Enter' to ignore: " MSTEAMS_WEBHOOK
fi

if [ -z "${MSTEAMS_WEBHOOK}" ] ; then
    MSTEAMS_WEBHOOK=NA
fi

SERVICE_PRINCIPAL_NAME=${DISAMBIG_PREFIX}sp

# Check AZ CLI status
msg "${GREEN}(1/4) Checking Azure CLI status...${NOFORMAT}"
{
  az > /dev/null
} || {
  msg "${RED}Azure CLI is not installed."
  msg "${GREEN}Go to https://aka.ms/nubesgen-install-az-cli to install Azure CLI."
  exit 1;
}
{
  az account show > /dev/null
} || {
  msg "${RED}You are not authenticated with Azure CLI."
  msg "${GREEN}Run \"az login\" to authenticate."
  exit 1;
}

msg "${YELLOW}Azure CLI is installed and configured!"

# Check GitHub CLI status
msg "${GREEN}(2/4) Checking GitHub CLI status...${NOFORMAT}"
USE_GITHUB_CLI=false
{
  gh auth status && USE_GITHUB_CLI=true && msg "${YELLOW}GitHub CLI is installed and configured!"
} || {
  msg "${YELLOW}Cannot use the GitHub CLI. ${GREEN}No worries! ${YELLOW}We'll set up the GitHub secrets manually."
  USE_GITHUB_CLI=false
}

# Create service principal with Contributor role in the subscription
msg "${GREEN}(3/4) Create service principal ${SERVICE_PRINCIPAL_NAME}"
SUBSCRIPTION_ID=$(az account show --query id --output tsv --only-show-errors)
w0=-w0
if [[ $OSTYPE == 'darwin'* ]]; then
  w0=
fi
SERVICE_PRINCIPAL=$(az ad sp create-for-rbac --name ${SERVICE_PRINCIPAL_NAME} --role="Contributor" --scopes="/subscriptions/${SUBSCRIPTION_ID}" --sdk-auth --only-show-errors | base64 $w0)
msg "${YELLOW}\"DISAMBIG_PREFIX\""
msg "${GREEN}${DISAMBIG_PREFIX}"

SP_ID=$(az ad sp list --display-name $SERVICE_PRINCIPAL_NAME --query \[0\].id -o tsv)
az role assignment create --assignee ${SP_ID} --scope="/subscriptions/${SUBSCRIPTION_ID}" --role "User Access Administrator"

# Create GitHub action secrets
AZURE_CREDENTIALS=$(echo $SERVICE_PRINCIPAL | base64 -d)

msg "${GREEN}(4/4) Create secrets in GitHub"
if $USE_GITHUB_CLI; then
  {
    msg "${GREEN}Using the GitHub CLI to set secrets.${NOFORMAT}"
    gh ${GH_FLAGS} secret set AZURE_CREDENTIALS -b"${AZURE_CREDENTIALS}"
    msg "${YELLOW}\"AZURE_CREDENTIALS\""
    msg "${GREEN}${AZURE_CREDENTIALS}"
    gh ${GH_FLAGS} secret set USER_NAME -b"${USER_NAME}"
    gh ${GH_FLAGS} secret set CLIENT_ID -b"${CLIENT_ID}"
    gh ${GH_FLAGS} secret set SECRET_VALUE -b"${SECRET_VALUE}"
    gh ${GH_FLAGS} secret set TENANT_ID -b"${TENANT_ID}"
    gh ${GH_FLAGS} secret set MSTEAMS_WEBHOOK -b"${MSTEAMS_WEBHOOK}"
    msg "${GREEN}Secrets configured"
  } || {
    USE_GITHUB_CLI=false
  }
fi
if [ $USE_GITHUB_CLI == false ]; then
  msg "${NOFORMAT}======================MANUAL SETUP======================================"
  msg "${GREEN}Using your Web browser to set up secrets..."
  msg "${NOFORMAT}Go to the GitHub repository you want to configure."
  msg "${NOFORMAT}In the \"settings\", go to the \"secrets\" tab and the following secrets:"
  msg "(in ${YELLOW}yellow the secret name and${NOFORMAT} in ${GREEN}green the secret value)"
  msg "${YELLOW}\"AZURE_CREDENTIALS\""
  msg "${GREEN}${AZURE_CREDENTIALS}"
  msg "${YELLOW}\"USER_NAME\""
  msg "${GREEN}${USER_NAME}"
  msg "${YELLOW}\"CLIENT_ID\""
  msg "${GREEN}${CLIENT_ID}"
  msg "${YELLOW}\"SECRET_VALUE\""
  msg "${GREEN}${SECRET_VALUE}"
  msg "${YELLOW}\"TENANT_ID\""
  msg "${GREEN}${TENANT_ID}"
  msg "${YELLOW}\"MSTEAMS_WEBHOOK\""
  msg "${GREEN}${MSTEAMS_WEBHOOK}"
  msg "${NOFORMAT}========================================================================"
fi
