#!/bin/bash
set -e -o pipefail

export REPO_ROOT=$(git rev-parse --show-toplevel)
PHASE="install"
source ${REPO_ROOT}/scripts/utils.sh

echo -e "\n${BOLD}${BLUE}🚀 Starting installation process...${NC}"

# Static helm values files
ARGOCD_STATIC_VALUES_FILE=${REPO_ROOT}/packages/argo-cd/values.yaml
EXTERNAL_SECRETS_STATIC_VALUES_FILE=${REPO_ROOT}/packages/external-secrets/values.yaml
CROSSPLANE_STATIC_VALUES_FILE=${REPO_ROOT}/packages/crossplane/values.yaml
ADDONS_APPSET_STATIC_VALUES_FILE=${REPO_ROOT}/packages/bootstrap/values.yaml

# Chart versions for Argo CD and ESO
ARGOCD_CHART_VERSION=$(yq '.argocd.defaultVersion' ${REPO_ROOT}/packages/addons/values.yaml)
EXTERNAL_SECRETS_CHART_VERSION=$(yq '.external-secrets.defaultVersion' ${REPO_ROOT}/packages/addons/values.yaml)
CROSSPLANE_CHART_VERSION=$(yq '.crossplane.defaultVersion' ${REPO_ROOT}/packages/addons/values.yaml)

# Custom Manifests Paths
ARGOCD_CUSTOM_MANIFESTS_PATH=${REPO_ROOT}/packages/argo-cd/manifests
EXTERNAL_SECRETS_CUSTOM_MANIFESTS_PATH=${REPO_ROOT}/packages/external-secrets/manifests
CROSSPLANE_CUSTOM_MANIFESTS_PATH=${REPO_ROOT}/packages/crossplane/manifests
CROSSPLANE_CUSTOM_MANIFESTS_DIRS=(providers clusterproviderconfig functions configurations xrs)

# Build Argo CD dynamic values
ARGOCD_DYNAMIC_VALUES_FILE=$(mktemp)
ISSUER_URL=$([[ "${PATH_ROUTING}" == "false" ]] && echo "keycloak.${DOMAIN_NAME}" || echo "${DOMAIN_NAME}/keycloak")
cat << EOF > ${ARGOCD_DYNAMIC_VALUES_FILE}
# Specific values for reference CNOE implementation to control extraObjects.
global:
  domain: $([[ "${PATH_ROUTING}" == "true" ]] && echo "${DOMAIN_NAME}" || echo "argocd.${DOMAIN_NAME}")
server:
  ingress:
    annotations:
      cert-manager.io/cluster-issuer: $([[ "${PATH_ROUTING}" == "false" ]] && echo '"letsencrypt-prod"' || echo "")
    path: /$([[ "${PATH_ROUTING}" == "true" ]] && echo "argocd" || echo "")
configs:
  cm:
    oidc.config: |
      name: Keycloak
      issuer: https://${ISSUER_URL}/realms/cnoe
      clientID: argocd
      enablePKCEAuthentication: true
      requestedScopes:
        - openid
        - profile
        - email
        - groups
  params:
    'server.basehref': /$([[ "${PATH_ROUTING}" == "true" ]] && echo "argocd" || echo "")
    'server.rootpath': $([[ "${PATH_ROUTING}" == "true" ]] && echo "argocd" || echo "")
EOF

echo -e "${BOLD}${GREEN}🔄 Installing Argo CD...${NC}"
helm repo add argo "https://argoproj.github.io/argo-helm" > /dev/null
helm repo update > /dev/null
helm upgrade --install --wait argocd argo/argo-cd \
  --namespace argocd --version ${ARGOCD_CHART_VERSION} \
  --create-namespace \
  --values "${ARGOCD_STATIC_VALUES_FILE}" \
  --values "${ARGOCD_DYNAMIC_VALUES_FILE}" \
  --kubeconfig ${KUBECONFIG_FILE} > /dev/null

echo -e "${YELLOW}⏳ Waiting for Argo CD to be healthy...${NC}"
kubectl wait --for=condition=available deployment/argocd-server -n argocd --timeout=300s --kubeconfig ${KUBECONFIG_FILE} > /dev/null


echo -e "${BOLD}${GREEN}🔄 Installing Crossplane...${NC}"
helm repo add crossplane "https://charts.crossplane.io/stable" > /dev/null
helm repo update > /dev/null
helm upgrade --install --wait crossplane crossplane/crossplane\
  --namespace crossplane-system --version ${CROSSPLANE_CHART_VERSION} \
  --create-namespace \
  --values "${CROSSPLANE_STATIC_VALUES_FILE}" \
  --kubeconfig ${KUBECONFIG_FILE} > /dev/null

echo -e "${YELLOW}⏳ Waiting for Crossplane to be healthy...${NC}"
kubectl wait --for=condition=available deployment/crossplane -n crossplane-system --timeout=300s --kubeconfig ${KUBECONFIG_FILE} > /dev/null

echo -e "${BOLD}${GREEN}🔄 Applying Crossplane custom manifests...${NC}"
for dir in ${CROSSPLANE_CUSTOM_MANIFESTS_DIRS[@]}; do
  for ns in $(yq '[.[].namespace | select(.!=null)] | .[]' ${CROSSPLANE_CUSTOM_MANIFESTS_PATH}/${dir}/*.yaml); do
    if [ $(kubectl get ns -o yaml --kubeconfig ${KUBECONFIG_FILE} | ns=${ns} yq '[.items[] | select(.metadata.name==env(ns))] | length') -eq 0 ]; then
      kubectl create ns $ns --kubeconfig ${KUBECONFIG_FILE} 2>&1 > /dev/null
    fi
  done
  kubectl apply -f ${CROSSPLANE_CUSTOM_MANIFESTS_PATH}/${dir} --kubeconfig ${KUBECONFIG_FILE}
  for pkg in $(kubectl get pkg -o name --kubeconfig ${KUBECONFIG_FILE}); do
    kubectl wait ${pkg} --for=condition=Healthy=true --kubeconfig ${KUBECONFIG_FILE} 2>&1 > /dev/null
  done
done
if [ $(kubectl get pkg -o yaml --kubeconfig ${KUBECONFIG_FILE} | yq '[.items[] | select(.spec.package=="*/provider-kubernetes:*")] | length') -eq 1 ]; then
  if [ $(kubectl get clusterrolebindings -o yaml | yq '[.items[] | select(.metadata.name=="provider-kubernetes-admin-binding")] | length') -eq 0 ]; then
    SA=$(kubectl -n crossplane-system get sa -o name --kubeconfig ${KUBECONFIG_FILE} | grep provider-kubernetes | sed -e 's|serviceaccount\/|crossplane-system:|g')
    kubectl create clusterrolebinding provider-kubernetes-admin-binding --clusterrole cluster-admin --serviceaccount="${SA}" --kubeconfig ${KUBECONFIG_FILE}
  fi
fi


echo -e "${BOLD}${GREEN}🔄 Installing External Secrets...${NC}"
helm repo add external-secrets "https://charts.external-secrets.io" > /dev/null
helm repo update > /dev/null
helm upgrade --install --wait external-secrets external-secrets/external-secrets \
  --namespace external-secrets --version ${EXTERNAL_SECRETS_CHART_VERSION} \
  --create-namespace \
  --values "${EXTERNAL_SECRETS_STATIC_VALUES_FILE}" \
  --kubeconfig ${KUBECONFIG_FILE} > /dev/null

echo -e "${YELLOW}⏳ Waiting for External Secrets to be healthy...${NC}"
kubectl wait --for=condition=available deployment/external-secrets -n external-secrets --timeout=300s --kubeconfig ${KUBECONFIG_FILE} > /dev/null


echo -e "${BOLD}${GREEN}🔄 Applying custom manifests...${NC}"
# sleep 60
kubectl apply -f ${ARGOCD_CUSTOM_MANIFESTS_PATH} --kubeconfig ${KUBECONFIG_FILE} > /dev/null
kubectl apply -f ${EXTERNAL_SECRETS_CUSTOM_MANIFESTS_PATH} --kubeconfig ${KUBECONFIG_FILE} > /dev/null

echo -e "${BOLD}${GREEN}🔄 Installing Addons AppSet Argo CD application...${NC}"
helm upgrade --install --wait addons-appset ${REPO_ROOT}/packages/charts/appset \
  --namespace argocd \
  --values "${ADDONS_APPSET_STATIC_VALUES_FILE}" \
  --kubeconfig ${KUBECONFIG_FILE} > /dev/null

# Wait for Argo CD applications to sync
sleep 10
wait_for_apps

echo -e "\n${BOLD}${BLUE}🎉 Installation completed successfully! 🎉${NC}"
echo -e "${CYAN}📊 You can now access your resources and start deploying applications.${NC}"
