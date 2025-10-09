# Crossplane-Driven Seed Deployment Tasks

## Objective
Reach full parity with the original Taskfile/Helmfile driven bootstrap by using only the `SeedInfrastructure` claim and the local Crossplane seed cluster to configure Azure identities, publish configuration to Key Vault, and deploy all CNOE addons through Argo CD/ApplicationSets.

## Task 1 – Claim Inputs & Chart Publishing ✅
- `seed/seed-infrastructure-claim.yaml.example` now carries every field required (Azure IDs, domain, repo metadata, routing flags, GitHub App placeholders, ApplicationSet chart location).
- The ApplicationSet chart is published under `charts/`; the claim points to the hosted index by default.

## Task 2 – Azure Workload Identities & Role Assignments ✅
- Reapplying the claim with the new `clientObjectId` parameter provisions all four user-assigned identities plus the bootstrap service principal role assignment.
- Role assignments now use `managementPolicies` so Crossplane no longer tries to patch immutable Azure RoleAssignment objects.

## Task 3 – Key Vault Configuration Parity ✅
- `keyvault-config` is successfully written to Azure Key Vault from the rendered `cnoe-config` secret.
- Service principal RBAC is handled automatically so secret updates can be re-applied without a local helper script.

## Task 4 – External DNS Credentials ✅
- The external-dns ApplicationSet now deploys an ExternalSecret sourced from Key Vault and creates the `/etc/kubernetes/azure.json` secret via Crossplane; the pod runs successfully and updates DNS records.

## Task 5 – ApplicationSet Sync & Observability 🚧
- *Argo Workflows*: server pod crash-loops because the `keycloak-oidc` secret is missing; external-secrets entry for Keycloak must be populated first.
- *Backstage*: PostgreSQL dependency fails (`backstage-env-vars` secret missing), so the main pod remains `ContainerCreating`.
- *External Secrets*: `github-app-org` still reports `SecretSyncedError` when Key Vault is missing GitHub values; verify Key Vault contains the populated fields after updates.
- *Keycloak*: server pod fails because `keycloak-config` secret is absent; ensure secrets exist before the chart starts.
- Next steps: populate required secrets via Key Vault, re-trigger external-secrets sync, and verify each addon reaches `Healthy`.

## Task 6 – Documentation & Taskfile Retirement ✅
- README, `docs/SEED_MANUAL.md`, and `AGENTS.md` now explain the Crossplane-only workflow, call out the new `clientObjectId` requirement, and summarise still-outstanding addon gaps.
