# Current Recovery Tasks

## Task 1 – Align Remote Azure Providers ☐
- Provider installs on the remote cluster use `xpkg.upbound.io/upbound/provider-azure-*` v2.x, but the existing `workloadidentity` composition still references the older `*.azure.m.upbound.io` API. Decide whether to downgrade the provider packages to a v1 release or update the manifests to the new API so CRDs exist.
- Ensure the Crossplane package manager (`upbound-controller-manager` service account) has the RBAC required to patch provider revisions; confirm `providerrevisions.pkg.crossplane.io` become `Healthy=True` once the API mismatch is resolved.
- Re-run `hack/reconcile.sh` after the change to verify pods and CRDs install cleanly.

## Task 2 – Restore Workload Identity & Secret Store ☐
- After Task 1, confirm the `workloadidentities.azure.livewyer.io` resources (external-dns, external-secrets, keycloak) reach `Synced=True` and Azure role assignments/federated credentials are created.
- Validate the `azure-keyvault` `ClusterSecretStore` is `Ready=True` and can mint tokens using the workload identity; watch the external-secrets controller logs for token acquisition success.
- Once the store works, verify ExternalSecrets (`github-app-org`, `hub-cluster-secret`, `external-dns-azure`) reach `SecretSynced=True` and their downstream secrets exist.

## Task 3 – Clear Degraded Addons ☐
- With secrets flowing, re-sync the addon applications (`argocd`, `external-dns`, `external-secrets`, `keycloak`, `backstage`, `argo-workflows`) until they report `Synced/Healthy`.
- Pay particular attention to ingress certificates and GitHub credentials for Argo CD; confirm the TLS secret and `github-app-org` secret are populated.
- Document the verification steps (e.g., `kubectl -n argocd get applications`, `kubectl -n external-dns get pods`) so future runs can be checked quickly.

## Task 4 – Update Runbooks & Automation ☐
- Capture the learnings (provider version requirements, identity creation order, reset script expectations) in `DESIGN.md`/`docs`.
- Consider extending the helper scripts to validate provider health post-deploy (simple `kubectl get providerrevisions` check) and to report Azure dependency drift earlier.
