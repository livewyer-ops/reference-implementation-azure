# Seed Deployment Design

## Goal
Stand up the CNOE reference implementation on Azure using a Crossplane-driven seed cluster so that remote AKS addons are reconciled declaratively from a single claim manifest.

## High-Level Topology
- **Local KinD Seed Cluster** hosts Crossplane, provider packages, and the Seed composition; no application workloads live here beyond the controllers.
- **Remote AKS Cluster** is the target for Argo CD, addons, and application namespaces; Crossplane connects via the uploaded kubeconfig secret.
- **Azure Subscription** supplies managed identities, DNS, Key Vault, and role assignments created by Crossplane providers.
- **Git Repositories** supply the ApplicationSet chart (hosted at `appsetChartRepository`) and the addons repo that Argo CD consumes.

## Component Flow
1. **Crossplane Core** is installed from `seed/crossplane-install.yaml` (static manifests). It provides:
   - `crossplane` and `crossplane-rbac-manager` deployments.
   - Required ClusterRoles/Bindings for provider workloads.

2. **Seed Composition Bundle** (`seed/seed-kickoff.yaml`) installs:
   - Provider packages (`provider-helm`, Azure providers, provider-kubernetes).
   - Crossplane function `function-patch-and-transform`.
   - `SeedInfrastructure` Composite Resource Definition and Composition.

3. **Claim Application** (`private/seed-infrastructure-claim.yaml`) triggers composition of:
   - Azure managed identities + role assignments for Crossplane and remote addons.
   - Azure DNS wildcard record and Key Vault.
   - Helm releases for Argo CD and the ApplicationSet chart via provider-helm.
   - Remote Kubernetes resources (namespace secrets/service accounts) using provider-kubernetes objects.

4. **Argo CD Bootstrap**
   - Helm release installs Argo CD into remote `argocd` namespace.
   - `cnoe` cluster secret carries annotations (repo URLs, Azure metadata) that drive ApplicationSets.
   - ApplicationSet chart renders addon ApplicationSets; each installs its chart (Backstage, Keycloak, etc.) plus extra manifests from `packages/<addon>/manifests`.

5. **Configuration Flow**
   - Claim parameters feed composition patches, populating annotation values for addons, identity names, DNS, Key Vault, Git info.
   - Provider-azure-managedidentity uses workload identity to create user-assigned identities, then provider-authorization binds roles.
   - Provider-kubernetes applies service accounts / secrets to remote AKS via the uploaded kubeconfig.
   - External Secrets controllers in AKS fetch configuration from Key Vault (populated by Crossplane using the seed cluster `cnoe-config` secret).

6. **Remote Addon Lifecycle**
   - ApplicationSets reconcile desired charts/values from the repo; Argo CD application health indicates addon status.
   - Azure credentials, GitHub App secrets, etc. live in Key Vault and are synced into namespaces via ExternalSecret resources.

## Operational Sequence
1. Reset KinD seed cluster (delete Crossplane providers/namespaces) and remote AKS addons when performing fresh runs.
2. Install Crossplane core (`seed/crossplane-install.yaml`), wait for deployments.
3. Apply `seed/seed-kickoff.yaml` to install providers and composition.
4. Upload remote kubeconfig secret (`cnoe-kubeconfig`).
5. Apply populated claim (`private/seed-infrastructure-claim.yaml`).
6. Monitor `seedinfrastructureclaims` and `seedinfrastructures` status; inspect composed resources for errors.
7. Validate Azure artifacts (managed identities, role assignments, DNS record, Key Vault) and remote Argo CD applications.
8. For cleanup, delete the claim, then remove Crossplane namespaces and remote addon namespaces, clearing finalizers as needed.

## Configuration Sources
- **Claim Parameters:** Domain, resource group, Key Vault name, Azure IDs, Git repo info, ApplicationSet chart metadata.
- **Secrets:**
  - `azure-service-principal` generated in seed cluster for Azure API access.
  - `cnoe-kubeconfig` uploaded manually to allow provider-helm/provider-kubernetes connections.
  - `private/seed-infrastructure-claim.yaml` (untracked) holds sensitive Azure/GitHub data.
- **Charts:**
  - ApplicationSet chart hosted in `charts/` and referenced via claim fields.
  - Addon chart values reside under `packages/` (identical to legacy branch).

## Error Handling & Observability
- Composition events surface in `kubectl describe seedinfrastructures`.
- Azure resource failures often stem from missing permissions or pre-existing objects (e.g., user-assigned identity already present) leading to reconciliation loops.
- Namespace deletion on AKS can stall due to Argo CD hook finalizers or Crossplane managed resources; must remove finalizers before retrying.
- Provider pods require workload identity annotations to access Azure; check service accounts under `crossplane-system`.

## Design Principles
- **Single Source of Truth:** the claim drives all configuration; no manual helm/task invocations on remote cluster.
- **Workload Identity:** Azure access occurs via managed identities rather than static credentials wherever possible.
- **Reconciliation Safety:** prefer deleting claims/providers to tear down infrastructure instead of ad-hoc kubectl deletes.
- **Modularity:** addons remain packaged under `packages/`; Crossplane composition simply orchestrates them.
- **Repeatability:** reset procedures must remove Azure resources or import them to avoid "resource already exists" errors.

# Comparison With Legacy Taskfile/Helm Workflow
- **Initiation:
  - *Legacy:* Taskfile orchestrated Helmfile to install Argo CD, ApplicationSets, and Crossplane directly on remote cluster.
  - *Current:* Local Crossplane seed cluster composes the entire stack from a single claim.

- **State Management:**
  - *Legacy:* Helmfile state stored locally; manual sequencing required (task install/diff/sync).
  - *Current:* Composition maintains desired state continuously; provider reconciliation handles drift.

- **Azure Credentials:**
  - *Legacy:* Helmfile invoked scripts that assumed manual provisioning of identities/role assignments or reused helper scripts.
  - *Current:* Composition creates managed identities/role assignments automatically, but fails if resource pre-exists (must import or delete manually).

- **Add-on Manifests:**
  - Both reuse `packages/` values/manifests; ApplicationSet chart behavior unchanged.

- **Failure Modes:**
  - *Legacy:* Failures surfaced at helm/task runtime; less automation but fewer hidden loops.
  - *Current:* Crossplane loops if Azure rejects operations (e.g., existing identity) or if provider permissions missing.

- **Cleanup:**
  - *Legacy:* Taskfile `uninstall` removed charts but left Azure artifacts untouched.
  - *Current:* Deleting the claim removes Azure resources, but also requires clearing finalizers to unblock namespace deletion.

## Known Gaps Impacting Reliability
1. **Pre-existing Azure Artifacts:** composition fails when identities/DNS/KeyVault already exist; need import strategy or automated detection.
2. **Provider Runtime Config:** provider pods must run with workload identity runtime config; incorrect ordering leaves providers stuck.
3. **Namespace Finalizers:** Argo CD hook finalizers and Crossplane managed-object finalizers require manual removal during teardown.
4. **Job Hook Residues:** Helm hook jobs/roles block namespace deletion post-claim deletion.
5. **Manual kubeconfig Secret:** provisioning sequence fails if `cnoe-kubeconfig` missing or stale.
6. **Azure RBAC Wait:** role assignment propagation delays can block downstream resources (Key Vault secrets, DNS updates).
7. **Observability Complexity:** diagnosing failures requires inspecting multiple CR types (SeedInfrastructure, provider statuses, external secrets).

## Next Steps
- Document teardown/import procedures to avoid orphaned Azure artifacts.
- Automate namespace finalizer cleanup via scripts or crossplane composition adjustments.
- Establish smoke tests after claim creation to confirm ExternalSecrets and key addons are healthy.
