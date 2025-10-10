# Seed Bootstrap Design

> Historical revisions are stored in `docs/archive/DESIGN.md`.

## Objectives
- Replace the legacy Taskfile/Helmfile bootstrap with a KinD-hosted Crossplane control plane.
- Leave `packages/` exactly as it is on `origin/v2` so Argo CD and remote Crossplane behave identically to the previous workflow.
- Limit seed-side responsibility to reproducing the Azure side effects and remote Helm releases that the Taskfile handled.

## Legacy Parity & Scope
- The seed cluster provisions user-assigned identities, role assignments, DNS records, the Key Vault secret, and the remote Crossplane/Argo CD Helm releases—mirroring the Taskfile CLI actions.
- Remote AKS keeps the same addons, values, and ApplicationSet structure; troubleshooting should first focus on seed automation before touching `packages/`.
- Helper scripts under `hack/` replace the Taskfile entry points: `deployment.sh` for bootstrap, `reconcile.sh` for reapply/resync, and `reset.sh` for teardown plus Azure cleanup.

## Seed Control Plane Responsibilities
- `seed/00-crossplane-core.yaml` renders the Crossplane core chart (namespace, service accounts, RBAC, deployments) on KinD.
- `seed/10-bootstrap-azure-providers.yaml` installs Azure providers (authorization, managedidentity, network, keyvault) with a workload-identity runtime config so they reuse the Crossplane service account.
- `seed/20-seed-composition.yaml` defines the `SeedInfrastructure` XRD/composition, installs provider-helm + function-patch-and-transform, and declares the managed resources and Helm releases produced by the claim.
- The composition creates:
  - Azure resources: user-assigned identities, federated credentials, role assignments, DNS zone/record, Key Vault and `config` secret.
  - Remote bootstrap assets: the Argo CD cluster secret, GitHub repo creds, workload identity annotations, the `cnoe-config` secret, and remote Crossplane Helm release parameters.
  - Provider-helm resources to install Argo CD/ApplicationSet on the remote cluster using the repo inputs from the claim.

## Remote Cluster Responsibilities
- Argo CD (installed by provider-helm) applies the untouched charts and values under `packages/`, matching the legacy GitOps flow.
- Remote Crossplane runs with the provider bundles defined in `packages/crossplane` (family-azure v2.0.0, sub-providers, provider-kubernetes) and manages addon identities/secrets as before.
- External Secrets, Backstage, and other addons rely on the Key Vault material populated by the seed composition; any gaps indicate bootstrap drift rather than package changes.

## Claim Inputs & Secrets
- The live claim (`private/seed-infrastructure-claim.yaml`) supplies domain, resource group, subscription, Key Vault name, GitHub app credentials, chart repo info, and identity names.
- Secrets: `private/kubeconfig` is projected into the seed via `cnoe-kubeconfig`; Azure SP credentials remain in `private/azure-credentials.json` and are never committed.
- Claim annotations feed patches in the composition to hydrate Argo CD secrets, workload identity specs, and provider configs.

## Automation Workflow
1. `hack/deployment.sh`
   - Creates the KinD cluster, applies Crossplane core, waits for controller readiness, then applies provider bootstrap + composition and the claim.
2. `hack/reconcile.sh`
   - Re-applies each seed manifest, waits for controllers, re-applies the claim, waits for it to be `Ready`, and issues Argo CD hard refreshes plus targeted pod restarts.
3. `hack/reset.sh`
   - Strips finalizers, force deletes remote Kubernetes resources, removes Azure identities/role assignments/Key Vault secrets (optionally the vault itself), and tears down the KinD cluster.

## Verification Guidance
- Seed: `kubectl --kubeconfig=private/seed-kubeconfig get providers.pkg.crossplane.io` and `kubectl get seedinfrastructureclaims.platform.livewyer.io`.
- Remote: `kubectl --kubeconfig=private/kubeconfig -n argocd get applications`, `kubectl --kubeconfig=private/kubeconfig get workloadidentities.azure.livewyer.io`, `kubectl --kubeconfig=private/kubeconfig get clustersecretstore azure-keyvault`.

## Known Gaps / Follow-Up
- Remote Azure providers still rely on the `.azure.m.upbound.io` API surface; ensure CRDs stay present when upgrading provider versions.
- External secret propagation and GitHub credentials remain flaky—investigate compositions and workload identities before touching package values.
- Reset script is intentionally aggressive; keep `AZ_PRESERVE_KEYVAULT=1` available and document any additional flags or Azure cleanup gotchas.
