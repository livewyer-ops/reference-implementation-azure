#!/usr/bin/env bash
set -xeuo pipefail

CLAIM_FILE="private/seed-infrastructure-claim.yaml"

if [[ -f "$CLAIM_FILE" ]]; then
  SUBSCRIPTION_ID=$(yq -r '.spec.parameters.subscriptionId' "$CLAIM_FILE")
  RESOURCE_GROUP=$(yq -r '.spec.parameters.resourceGroup' "$CLAIM_FILE")
  KEYVAULT_NAME=$(yq -r '.spec.parameters.keyVaultName' "$CLAIM_FILE")
  DOMAIN_NAME=$(yq -r '.spec.parameters.domain' "$CLAIM_FILE")
  CLUSTER_NAME=$(yq -r '.spec.parameters.clusterName' "$CLAIM_FILE")
  LOCATION=$(yq -r '.spec.parameters.location' "$CLAIM_FILE")
  CLIENT_OBJECT_ID=$(yq -r '.spec.parameters.clientObjectId' "$CLAIM_FILE")
  CROSSPLANE_IDENTITY_NAME=$(yq -r '.spec.parameters.crossplaneIdentityName // "crossplane"' "$CLAIM_FILE")
  EXTERNAL_DNS_IDENTITY_NAME=$(yq -r '.spec.parameters.externalDnsIdentityName // "external-dns"' "$CLAIM_FILE")
  EXTERNAL_SECRETS_IDENTITY_NAME=$(yq -r '.spec.parameters.externalSecretsIdentityName // "external-secrets"' "$CLAIM_FILE")
  KEYCLOAK_IDENTITY_NAME=$(yq -r '.spec.parameters.keycloakIdentityName // "keycloak"' "$CLAIM_FILE")
else
  SUBSCRIPTION_ID=""
fi

for kind in applications.argoproj.io applicationsets.argoproj.io externalsecrets.external-secrets.io workloadidentities.azure.livewyer.io objects.kubernetes.m.crossplane.io; do
  kubectl --kubeconfig=private/kubeconfig get "$kind" -A -o json 2>/dev/null | jq -r '.items[] | [.metadata.namespace, .metadata.name] | @tsv' |
    while IFS=$'\t' read -r ns name; do
      kubectl --kubeconfig=private/kubeconfig patch "$kind" "$name" -n "$ns" --type=merge -p '{"metadata":{"finalizers":[]}}' || true
      kubectl --kubeconfig=private/kubeconfig delete "$kind" "$name" -n "$ns" --grace-period=0 --force || true
    done
done

for ns in argocd external-dns external-secrets cert-manager ingress-nginx backstage keycloak crossplane-system; do
  if kubectl --kubeconfig=private/kubeconfig get namespace "$ns" &>/dev/null; then
    kubectl --kubeconfig=private/kubeconfig patch namespace "$ns" --type=json -p='[{"op":"remove","path":"/metadata/finalizers"}]' || true
  fi
done

kubectl --kubeconfig=private/kubeconfig get clustersecretstores.external-secrets.io -o json 2>/dev/null | jq -r '.items[].metadata.name' |
  while read -r name; do
    kubectl --kubeconfig=private/kubeconfig patch clustersecretstore "$name" --type=merge -p '{"metadata":{"finalizers":[]}}' || true
    kubectl --kubeconfig=private/kubeconfig delete clustersecretstore "$name" --grace-period=0 --force || true
  done

kubectl --kubeconfig=private/kubeconfig delete applications.argoproj.io --all -n argocd --grace-period=0 --force || true
kubectl --kubeconfig=private/kubeconfig delete applicationsets.argoproj.io --all -n argocd --grace-period=0 --force || true
kubectl --kubeconfig=private/kubeconfig delete externalsecrets.external-secrets.io --all --all-namespaces --grace-period=0 --force || true
kubectl --kubeconfig=private/kubeconfig delete workloadidentities.azure.livewyer.io --all --all-namespaces --grace-period=0 --force || true
kubectl --kubeconfig=private/kubeconfig delete secrets --all -n argocd --grace-period=0 --force || true
kubectl --kubeconfig=private/kubeconfig delete namespace argocd external-dns external-secrets cert-manager ingress-nginx backstage keycloak crossplane-system --grace-period=0 --force --ignore-not-found || true

kubectl --kubeconfig=private/kubeconfig delete clusterrolebinding provider-kubernetes-admin-binding --ignore-not-found || true

if [[ -n "${SUBSCRIPTION_ID:-}" ]] && command -v az >/dev/null 2>&1; then
  az account set --subscription "$SUBSCRIPTION_ID" --only-show-errors || true

  for IDENTITY in "$CROSSPLANE_IDENTITY_NAME" "$EXTERNAL_DNS_IDENTITY_NAME" "$EXTERNAL_SECRETS_IDENTITY_NAME" "$KEYCLOAK_IDENTITY_NAME"; do
    az identity delete --name "$IDENTITY" --resource-group "$RESOURCE_GROUP" --only-show-errors || true
  done

  CROSSPLANE_PRINCIPAL=$(az identity show --name "$CROSSPLANE_IDENTITY_NAME" --resource-group "$RESOURCE_GROUP" --query 'principalId' -o tsv --only-show-errors 2>/dev/null || true)
  if [[ -n "$CROSSPLANE_PRINCIPAL" ]]; then
    az role assignment delete \
      --assignee-object-id "$CROSSPLANE_PRINCIPAL" \
      --scope "/subscriptions/$SUBSCRIPTION_ID/resourceGroups/$RESOURCE_GROUP" \
      --only-show-errors || true
  fi

  if [[ -n "${CLIENT_OBJECT_ID:-}" ]]; then
    az role assignment delete \
      --assignee-object-id "$CLIENT_OBJECT_ID" \
      --scope "/subscriptions/$SUBSCRIPTION_ID/resourceGroups/$RESOURCE_GROUP/providers/Microsoft.KeyVault/vaults/$KEYVAULT_NAME" \
      --only-show-errors || true
  fi

  az keyvault secret delete --vault-name "$KEYVAULT_NAME" --name config --only-show-errors || true
  az keyvault secret purge --vault-name "$KEYVAULT_NAME" --name config --only-show-errors || true
  az keyvault secret delete --vault-name "$KEYVAULT_NAME" --name github-private-key --only-show-errors || true
  az keyvault secret purge --vault-name "$KEYVAULT_NAME" --name github-private-key --only-show-errors || true

  if [[ -z "${AZ_PRESERVE_KEYVAULT:-}" ]]; then
    az keyvault delete --name "$KEYVAULT_NAME" --resource-group "$RESOURCE_GROUP" --only-show-errors || true
    az keyvault purge --name "$KEYVAULT_NAME" --location "$LOCATION" --only-show-errors || true
  fi

  if [[ -n "${CLUSTER_NAME:-}" && -n "${DOMAIN_NAME:-}" ]]; then
    WILDCARD_RECORD="${CLUSTER_NAME}-wildcard"
    az network dns record-set a delete \
      --resource-group "$RESOURCE_GROUP" \
      --zone-name "$DOMAIN_NAME" \
      --name "$WILDCARD_RECORD" \
      --yes \
      --only-show-errors || true
  fi
fi

kind delete cluster --name seed || true
rm -f private/seed-kubeconfig
