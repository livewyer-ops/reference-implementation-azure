# Crossplane-Driven Seed Deployment Tasks

## Objective
Reach full parity with the original Taskfile/Helmfile driven bootstrap by using only the `SeedInfrastructure` claim and the local Crossplane seed cluster to configure Azure identities, publish configuration to Key Vault, and deploy all CNOE addons through Argo CD/ApplicationSets.

## Task 1 – Claim Inputs & Chart Publishing ✅
- `seed/seed-infrastructure-claim.yaml.example` now carries every field required (Azure IDs, domain, repo metadata, routing flags, GitHub App placeholders, ApplicationSet chart location).
- The ApplicationSet chart is published under `charts/`; the claim points to the hosted index by default.

## Task 2 – Azure Workload Identities & Role Assignments
- Reproduce `azure:creds` and `azure:creds:get` by composing Crossplane resources that create the required Azure User Assigned Managed Identities, federated credentials, and role assignments:
  - `crossplane` identity (Owner on the resource group) used by Crossplane providers.
  - `external-dns`, `external-secrets`, and `keycloak` identities with the same role scopes as the Taskfile automation.
- Expose identity client IDs/tenant IDs back into the claim outputs so helm/appset templates consume them.
- Ensure `deletionPolicy` is set so these identities are cleaned up when the claim is removed.

## Task 3 – Key Vault Configuration Parity
- The Taskfile pushes `config.yaml` into Azure Key Vault (`config` secret). Add a managed resource (e.g., `keyvault.azure.upbound.io/Secret`) so the same JSON payload from the claim is written to the Key Vault identified by `keyVaultName`.
- Confirm updates/rotations (claim reapply) refresh the Key Vault secret as the CLI did.

## Task 4 – External DNS Credentials
- Replace the pod-mounted `/etc/kubernetes/azure.json` dependency so `external-dns` can authenticate:
  - Either reference the workload identity created in Task 2, or
  - Compose a Secret containing the minimal Azure config sourced from the claim parameters.
- Verify the `external-dns` Deployment leaves CrashLoopBackOff and reconciles records in the target DNS zone.

## Task 5 – ApplicationSet Sync & Observability
- Wait for/trigger Argo CD sync for each generated `Application` and confirm health statuses reach `Synced`.
- Surface helpful status/connection details (e.g., Argo CD URL, repo URL) via composition outputs to aid troubleshooting.
- Document that GitHub App values default to anonymous access (public repo) but can be overridden without altering the composition.

## Task 6 – Documentation & Taskfile Retirement
- Update README/AGENTS/dosc to describe the Azure identity + Key Vault behaviour and external-dns requirements.
- Remove any residual instructions that reference `Taskfile.yml`/Helmfile once parity tasks above are implemented.
- Add troubleshooting/rotation guidance (GitHub App credentials, Azure identity role scope, Key Vault secret refresh).
