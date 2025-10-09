#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SEED_KUBECONFIG="${ROOT_DIR}/private/seed-kubeconfig"
REMOTE_KUBECONFIG="${REMOTE_KUBECONFIG:-${ROOT_DIR}/private/kubeconfig}"
CLUSTER_SECRET="${CLUSTER_CONNECTION_SECRET_NAME:-cnoe-kubeconfig}"

if [[ ! -f "${REMOTE_KUBECONFIG}" ]]; then
  echo "Remote kubeconfig not found at ${REMOTE_KUBECONFIG}. Set REMOTE_KUBECONFIG to override." >&2
  exit 1
fi

mkdir -p "${ROOT_DIR}/private"

kind create cluster --config "${ROOT_DIR}/kind.yaml" --name seed
kind get kubeconfig --name seed > "${SEED_KUBECONFIG}"
export KUBECONFIG="${SEED_KUBECONFIG}"

kubectl apply -f "${ROOT_DIR}/seed/crossplane-install.yaml"
kubectl -n crossplane-system wait deployment/crossplane deployment/crossplane-rbac-manager \
  --for=condition=Available --timeout=10m

kubectl apply -f "${ROOT_DIR}/seed/seed-kickoff.yaml"
kubectl create secret generic "${CLUSTER_SECRET}" \
  -n crossplane-system \
  --from-file=kubeconfig="${REMOTE_KUBECONFIG}" \
  --dry-run=client -o yaml | kubectl apply -f -

kubectl apply -f "${ROOT_DIR}/seed/seed-infrastructure-claim.yaml"
