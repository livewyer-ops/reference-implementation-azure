#!/usr/bin/env bash
set -xeuo pipefail

kind create cluster --config kind.yaml --name seed
kind get kubeconfig --name seed >private/seed-kubeconfig
export KUBECONFIG="$(pwd)/private/seed-kubeconfig"

# Bootstrap Crossplane core first so CRDs exist before other applies.
kubectl apply -f seed/00-crossplane-core.yaml
kubectl wait deployment/crossplane -n crossplane-system --for=condition=Available --timeout=10m
kubectl wait deployment/crossplane-rbac-manager -n crossplane-system --for=condition=Available --timeout=10m

kubectl apply -f seed/10-bootstrap-azure-providers.yaml
kubectl apply -f seed/20-seed-composition.yaml

kubectl create secret generic cnoe-kubeconfig \
  -n crossplane-system \
  --from-file=kubeconfig=private/kubeconfig \
  --dry-run=client -o yaml | kubectl apply -f -

kubectl apply -f private/seed-infrastructure-claim.yaml
