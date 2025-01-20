#!/bin/bash
set -e -o pipefail

REPO_ROOT=$(git rev-parse --show-toplevel)
SETUP_DIR="${REPO_ROOT}/setups"
TF_DIR="${REPO_ROOT}/terraform"
source ${REPO_ROOT}/setups/utils.sh

cd ${SETUP_DIR}

echo -e "${PURPLE}\nTargets:${NC}"
echo "Kubernetes cluster: $(kubectl config current-context)"
echo "Azure account (if set): $(az account show -o json | jq -rc '.user.name')"
echo "Azure subscription: $(az account show -o json | jq -rc '.name')"

echo -e "${RED}\nAre you sure you want to continue?${NC}"
read -p '(yes/no): ' response
if [[ ! "$response" =~ ^[Yy][Ee][Ss]$ ]]; then
  echo 'exiting.'
  exit 0
fi

cd "${TF_DIR}"
terraform destroy

cd "${SETUP_DIR}/argocd/"
./uninstall.sh
cd -
