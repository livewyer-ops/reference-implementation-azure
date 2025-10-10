#!/usr/bin/env bash
set -xeuo pipefail

kind create cluster --config kind.yaml --name seed
kind get kubeconfig --name seed >private/seed-kubeconfig
export KUBECONFIG="$(pwd)/private/seed-kubeconfig"

kubectl apply -f seed/
kubectl create secret generic cnoe-kubeconfig \
  -n crossplane-system \
  --from-file=kubeconfig=private/kubeconfig \
  --dry-run=client -o yaml | kubectl apply -f -

kubectl apply -f private/seed-infrastructure-claim.yaml
