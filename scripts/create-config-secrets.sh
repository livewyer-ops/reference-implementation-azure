#!/bin/bash
set -e -o pipefail

export REPO_ROOT=$(git rev-parse --show-toplevel)
SECRET_NAME_PREFIX="cnoe-ref-impl"
PHASE="create-update-secrets"
source ${REPO_ROOT}/scripts/utils.sh

PRIVATE_DIR="${REPO_ROOT}/private"

echo -e "\n${BOLD}${BLUE}🔐 Starting secret creation process...${NC}"
echo -e "${CYAN}📂 Reading files from:${NC} ${BOLD}${PRIVATE_DIR}${NC}"

if [ ! -d "${PRIVATE_DIR}" ]; then
  echo -e "${RED}❌ Directory ${PRIVATE_DIR} does not exist${NC}"
  exit 1
fi

# Create keyvault if doesn't exist
if [ $(az keyvault list -o yaml | SECRET_NAME_PREFIX=${SECRET_NAME_PREFIX} yq '.[] | [select(.name==env(SECRET_NAME_PREFIX))] | length') -eq 0 ]; then
  if az keyvault create --resource-group ${AZURE_RESOURCE_GROUP} ${SECRET_NAME_PREFIX}; then
    echo -e "${GREEN}✅ Key Vault '${BOLD}${SECRET_NAME_PREFIX}${NC}${GREEN}' created successfully!${NC}"
  fi
fi

# Create or update secret
create_update_secret() {
  echo -e "\n${PURPLE}🚀 Creating/updating Secret for ${1}...${NC}"
  TAGS=$(get_tags_from_config)
  if az keyvault secret set \
    --name ${1} \
    --vault-name ${SECRET_NAME_PREFIX} \
    --file ${TEMP_SECRET_FILE} \
    --description "Secret for ${1} of CNOE Azure Reference Implementation" \
    --tags ${TAGS} >/dev/null 2>&1; then
    echo -e "${GREEN}✅ Secret '${BOLD}${SECRET_NAME_PREFIX}/${1}${NC}${GREEN}' created successfully!${NC}"
  else
    echo -e "${RED}❌ Failed to create/update secret${NC}"
    rm "${TEMP_SECRET_FILE}"
    exit 1
  fi

  # Cleanup
  rm "${TEMP_SECRET_FILE}"
  echo -e "${CYAN}🔐 Secret:${NC} $(az keyvault secret show --name ${1} --vault-name ${SECRET_NAME_PREFIX} --output yaml | yq '.id')"
}

echo -e "\n${YELLOW}📋 Processing files...${NC}"
TEMP_SECRET_FILE=$(mktemp)
echo "{}" > ${TEMP_SECRET_FILE}

# Start building JSON for Github App secrets
if [ $(find ${PRIVATE_DIR} -iname "*.yaml" | wc -l) -eq 0 ]; then
  echo -e "${RED}❌ No files found in ${PRIVATE_DIR}${NC}"
  rm "${TEMP_SECRET_FILE}"
  exit 1
fi

for file in "${PRIVATE_DIR}"/*.yaml; do
  if [ -f "${file}" ]; then
    filename=$(basename "${file}" .yaml)
    echo -e "${CYAN}  📄 Adding:${NC} ${filename}"

    # Add key-value pair with properly escaped content
    JQ_TEMP=$(mktemp)
    cp "${TEMP_SECRET_FILE}" "${JQ_TEMP}"
    jq --arg key "${filename}" --argjson data "$(yq -o=json eval '.' "${file}")" '. += {$key: $data}' ${JQ_TEMP} > ${TEMP_SECRET_FILE}
    rm "${JQ_TEMP}"
  fi
done

create_update_secret "github-app"

# Build JSON for Config secret
TEMP_SECRET_FILE=$(mktemp)
yq -o=json eval '.' "${CONFIG_FILE}" > "${TEMP_SECRET_FILE}"
create_update_secret "config"

# Create Crossplane cloud provider credentials
CROSSPLANE_AZURE_CREDS="${PRIVATE_DIR}/credentials.json"
CROSSPLANE_AZURE_SECRET="provider-azure"
CROSSPLANE_AZURE_SECRET_KEY="credential"
CROSSPLANE_NS="crossplane-system"

echo -e "\n${PURPLE}🚀 Creating/updating Secret for ${BOLD}${CROSSPLANE_NS}/${CROSSPLANE_AZURE_SECRET}[${CROSSPLANE_AZURE_SECRET_KEY}]...${NC}"

if [ ! -f ${CROSSPLANE_AZURE_CREDS} ]; then
  echo -e "${RED}❌ No credentials.json found in ${PRIVATE_DIR}${NC}"
  exit 1
fi

get_kubeconfig

if [ $(kubectl get ns -o yaml --kubeconfig ${KUBECONFIG_FILE} | ns=${CROSSPLANE_NS} yq '[.items[] | select(.metadata.name==env(ns))] | length') -eq 0 ]; then
  kubectl create ns ${CROSSPLANE_NS} --kubeconfig ${KUBECONFIG_FILE}
fi

if [ $(kubectl get secret -o yaml -n ${CROSSPLANE_NS} --kubeconfig ${KUBECONFIG_FILE} | secret=${CROSSPLANE_AZURE_SECRET} yq '[.items[] | select(.metadata.name==env(secret))] | length') -ne 0 ]; then
  kubectl delete secret ${CROSSPLANE_AZURE_SECRET} --interactive=false -n ${CROSSPLANE_NS} --kubeconfig ${KUBECONFIG_FILE} 1>/dev/null
fi

if kubectl create secret generic ${CROSSPLANE_AZURE_SECRET} -n ${CROSSPLANE_NS} --from-file=${CROSSPLANE_AZURE_SECRET_KEY}=${CROSSPLANE_AZURE_CREDS} --kubeconfig ${KUBECONFIG_FILE} 1>/dev/null; then
  echo -e "${GREEN}✅ Secret: '${BOLD}${CROSSPLANE_NS}/${CROSSPLANE_AZURE_SECRET}[${CROSSPLANE_AZURE_SECRET_KEY}]${NC}${GREEN}' created successfully!${NC}"
else
  echo -e "${RED}❌ Failed to create/update secret${NC}"
  exit 1
fi

echo -e "\n${BOLD}${GREEN}🎉 Process completed successfully! 🎉${NC}"
