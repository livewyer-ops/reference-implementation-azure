#!/usr/bin/env bash
set -euo pipefail

kubectl --kubeconfig=private/seed-kubeconfig apply -f seed/00-crossplane-core.yaml
kubectl --kubeconfig=private/seed-kubeconfig wait deployment/crossplane -n crossplane-system --for=condition=Available --timeout=10m
kubectl --kubeconfig=private/seed-kubeconfig wait deployment/crossplane-rbac-manager -n crossplane-system --for=condition=Available --timeout=10m

kubectl --kubeconfig=private/seed-kubeconfig apply -f seed/10-bootstrap-azure-providers.yaml
kubectl --kubeconfig=private/seed-kubeconfig wait deployment/provider-helm-c4d1cb4e84cf -n crossplane-system --for=condition=Available --timeout=10m
kubectl --kubeconfig=private/seed-kubeconfig wait deployment/function-patch-and-transform-3160a4debc89 -n crossplane-system --for=condition=Available --timeout=10m

kubectl --kubeconfig=private/seed-kubeconfig apply -f seed/20-seed-composition.yaml
kubectl --kubeconfig=private/seed-kubeconfig apply -f private/seed-infrastructure-claim.yaml
kubectl --kubeconfig=private/seed-kubeconfig wait seedinfrastructureclaims.platform.livewyer.io/seed-default --for=condition=Ready --timeout=10m

kubectl --kubeconfig=private/kubeconfig -n argocd annotate applicationsets.argoproj.io --all argocd.argoproj.io/refresh=hard --overwrite || true
kubectl --kubeconfig=private/kubeconfig -n argocd annotate applications.argoproj.io --all argocd.argoproj.io/refresh=hard --overwrite || true

kubectl --kubeconfig=private/kubeconfig -n argocd rollout restart deployment/argocd-application-controller || true
kubectl --kubeconfig=private/kubeconfig -n argocd rollout restart deployment/argocd-repo-server || true
kubectl --kubeconfig=private/kubeconfig -n external-secrets rollout restart deployment/external-secrets || true
