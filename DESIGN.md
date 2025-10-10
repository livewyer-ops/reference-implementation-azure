# Seed Deployment Design

## Goal
Stand up the CNOE reference implementation on Azure using a Crossplane-driven seed cluster so that remote AKS addons are reconciled declaratively from a single claim manifest.

## High-Level Topology
- **Seed Control Plane (KinD)** hosts Crossplane, a minimal set of provider packages, and the Seed composition. Its job is to bootstrap Azure prerequisites and publish remote Helm releases—no production workloads run here.
- **Remote Control Plane (AKS)** runs its own Crossplane installation (deployed via Argo CD) plus all addon workloads. This mirrors the legacy Helmfile model: Crossplane on AKS continuously reconciles addons and remote Azure dependencies.
- **Azure Subscription** supplies managed identities, DNS, Key Vault, and role assignments created either by the seed bootstrapper or by the remote Crossplane.
- **Git Repositories** supply the ApplicationSet chart (hosted at `appsetChartRepository`) and the addons repo that Argo CD consumes.

## Legacy Alignment & Scope
- The previous `v2` branch used a Taskfile/Helmfile workflow: local `az` CLI commands primed Azure assets and Helm traffic deployed addons into the remote cluster.
- The new seed-driven approach replaces those scripts with Crossplane automation on the KinD seed cluster. Every Azure side effect previously handled via CLI is now expressed as managed resources in the composition.
- Remote AKS remains aligned to the legacy topology. We intentionally avoid reworking addon manifests or Argo CD structure; the product surface (charts, values, namespaces) should be indistinguishable from the Taskfile/Helmfile output.
- Success is measured by delivering the same end-state as the `v2` workflow while reducing manual steps. Any divergence from the legacy configuration must be called out explicitly before implementation.

## Control-Plane Roles
1. **Seed Crossplane (KinD)** – performs bootstrap duties only:
   - Create or reconcile Azure identities, role assignments, DNS wildcard, and Key Vault.
   - Install Argo CD and the ApplicationSet chart on AKS—the same charts Helmfile previously deployed, now driven by provider-helm.
   - Install the remote Crossplane Helm release and seed its initial secrets so that the remote cluster behaves exactly as it did in the Helmfile workflow.
2. **Remote Crossplane (AKS)** – assumes full responsibility for the addon stack:
   - Uses provider packages (Azure + provider-kubernetes) to manage addon namespaces, ExternalSecrets, certificates, etc.
   - Matches the Helm/Taskfile Crossplane deployment one-for-one; only the bootstrap path changed.
   - Continuously reconciles addons driven by ApplicationSets in Argo CD.

## Component Flow – Seed Stage (KinD)
1. **Crossplane Core** – installed from `seed`; provides the control-plane deployments and RBAC on KinD.
2. **Bootstrap Provider Bundle & Runtime Config** – manifests under `seed/` (or a dedicated bootstrap bundle) install:
   - Azure provider(s) needed for bootstrap tasks (managed identity, DNS, Key Vault).
   - A runtime config for workload identity and any helper jobs (e.g., provider-kubernetes admin binding) required for bootstrap operations.
3. **Seed Composition (`seed/seed/20-seed-composition.yaml`)** – defines the `SeedInfrastructure` composition, installs provider-helm, and wires the bootstrap logic.

## Component Flow – Remote Stage (AKS)
4. **Claim Application** (`private/seed-infrastructure-claim.yaml`) instructs the seed Crossplane to:
   - Create Azure prerequisites (identities, role assignments, Key Vault secret).
   - Install Argo CD + ApplicationSet chart via provider-helm, mirroring the legacy Helm deployments.
   - Install the remote Crossplane Helm release, including its bootstrap secret (`cnoe-config`) and annotations, matching the artefacts previously rendered by Helmfile.
5. **Argo CD Responsibilities**
   - Reconcile the remote Crossplane Helm release and apply `packages/crossplane/kustomize/` + `packages/crossplane/manifests/` inside AKS (provider packages, runtime config).
   - Render addon ApplicationSets using data from the `cnoe` cluster secret.
6. **Remote Crossplane Responsibilities**
   - Manage addon namespaces, workloads, and per-addon Azure objects exactly as in the legacy Helmfile flow.
   - Seed injects the `provider-azure` secret so the remote Crossplane authenticates to Azure with the same credentials used for bootstrap.
   - Consume data rendered by ApplicationSets (chart versions, values) to deploy Backstage, Keycloak, External Secrets, etc.

## Operational Sequence
1. Reset KinD seed cluster (remove previous Crossplane/providers) and ensure remote AKS is clean before starting.
2. Install the seed control plane stack with a single command: `kubectl apply -k seed` (Crossplane core + bootstrap providers + composition). Wait for `crossplane`/`crossplane-rbac-manager` deployments to be Available.
3. Upload remote kubeconfig secret (`cnoe-kubeconfig`) to `crossplane-system` (KinD).
4. Apply the populated claim (`private/seed-infrastructure-claim.yaml`) to execute the same Azure and Helm bootstrap steps that the Taskfile performed, now codified inside Crossplane.
5. Monitor `seedinfrastructureclaims` / `seedinfrastructures`, provider statuses, and Azure resource CRs until Synced/Ready.
6. Confirm Argo CD and remote Crossplane pods are Healthy on AKS (read-only checks). ApplicationSets should then reconcile addons.
7. Verify remote AKS state using read-only commands—do not apply manifests directly; remote Crossplane owns ongoing reconciliation.
8. For cleanup, delete the claim first, wait for composed resources to disappear, then remove bootstrap providers and Crossplane from KinD; only clear remote finalizers if the claim has already been removed.

## Configuration Sources
- **Claim Parameters:** Domain, resource group, Key Vault name, Azure IDs, Git repo info, ApplicationSet chart metadata.
- **Secrets:**
  - `azure-service-principal` generated in seed cluster for Azure API access.
  - `cnoe-kubeconfig` uploaded manually to allow provider-helm/provider-kubernetes connections.
  - `private/seed-infrastructure-claim.yaml` (untracked) holds sensitive Azure/GitHub data.
  - Remote Crossplane bootstrap secrets (e.g., `cnoe-config`) are written by the seed composition and consumed by Argo CD.
- **Charts:**
  - ApplicationSet chart hosted in `charts/` and referenced via claim fields.
  - Remote Crossplane Helm release + addon charts are reconciled by Argo CD in AKS.

## Error Handling & Observability
- Seed composition events surface in `kubectl describe seedinfrastructures`.
- Remote Crossplane status mirrors addon health; inspect `kubectl --kubeconfig=... -n crossplane-system get providers.pkg.crossplane.io` on AKS.
- Azure resource failures often stem from missing permissions or pre-existing objects (e.g., user-assigned identity already present) leading to reconciliation loops—check both seed and remote provider logs.
- Namespace deletion on AKS can stall due to Argo CD hook finalizers or Crossplane managed resources; remove finalizers only after the claim has been deleted.
- Provider pods require workload identity annotations to access Azure; check service accounts in both seed and remote `crossplane-system` namespaces.

## Design Principles
- **Dual Control Planes:** seed Crossplane handles bootstrap, remote Crossplane handles day-2 addon reconciliation—never bypass either with manual changes.
- **Single Source of Truth:** the claim drives bootstrap configuration; ApplicationSets and remote Crossplane own addon state.
- **Workload Identity:** Azure access occurs via managed identities rather than static credentials wherever possible.
- **Reconciliation Safety:** prefer deleting claims/providers to tear down infrastructure instead of ad-hoc kubectl deletes.
- **Modularity:** addons remain packaged under `packages/`; remote Crossplane (via Argo CD) orchestrates them.
- **Repeatability:** reset procedures must remove Azure resources or import them to avoid "resource already exists" errors.

# Comparison With Legacy Taskfile/Helm Workflow
- **Initiation:**
  - *Legacy:* Taskfile orchestrated Helmfile to install Argo CD, ApplicationSets, and Crossplane directly on AKS.
  - *New:* Seed claim bootstraps Azure + installs Argo CD/remote Crossplane; remote Crossplane then behaves exactly as the legacy release.

- **State Management:**
  - *Legacy:* Helmfile state stored locally; manual sequencing required (task install/diff/sync).
  - *New:* Seed handles bootstrap; remote Crossplane + Argo CD maintain addon state continuously inside AKS.

- **Azure Credentials:**
  - *Legacy:* Helmfile invoked scripts that assumed manual provisioning of identities/role assignments or reused helper scripts.
  - *New:* Seed composition creates bootstrap identities/Key Vault/DNS; remote Crossplane continues to own addon-specific Azure resources.

- **Add-on Manifests:**
  - Both reuse `packages/` values/manifests; ApplicationSet behavior unchanged. Remote Crossplane now consumes them exactly as before.

- **Failure Modes:**
  - *Legacy:* Failures surfaced at helm/task runtime.
  - *New:* Failures can occur in either control plane; watch both seed and remote Crossplane provider status for issues.

- **Cleanup:**
  - *Legacy:* Taskfile `uninstall` removed charts but left Azure artifacts untouched.
  - *New:* Deleting the claim removes bootstrap artifacts; remote Crossplane/Argo CD continue to manage addon teardown.

## Known Gaps Impacting Reliability
1. **Pre-existing Azure Artifacts:** bootstrap still fails if identities/DNS/KeyVault already exist; must support import or detection.
2. **Provider Runtime Config (Seed & Remote):** both control planes need workload identity runtime configs applied in the right order.
3. **Namespace Finalizers:** Argo CD hook finalizers and Crossplane managed-object finalizers still require manual removal during teardown.
4. **Manual kubeconfig Secret:** provisioning sequence fails if `cnoe-kubeconfig` missing or stale.
5. **Azure RBAC Wait:** role assignment propagation delays can block downstream resources (Key Vault secrets, DNS updates).
6. **Dual Observability:** diagnosing issues requires watching both seed (`seedinfrastructure`, seed providers) and remote Crossplane providers/apps.

## Next Steps
- Document teardown/import procedures to avoid orphaned Azure artifacts.
- Automate namespace finalizer cleanup via scripts or crossplane composition adjustments.
- Establish smoke tests after claim creation to confirm remote Crossplane providers and key addons are healthy.

## Installation Checklist (Parity with Helmflow)
1. **Seed Reset (Optional)**
   - `kubectl delete -f seed` and `seed/seed/20-seed-composition.yaml` only after the claim is removed and all composed resources are gone.
   - Ensure seed cluster namespaces (`crossplane-system`, `seed-system`) and Crossplane providers are absent before reinstalling.

2. **Crossplane Bootstrapping Order**
   - `kubectl apply -k seed`; wait for `crossplane` and `crossplane-rbac-manager` deployments to be Available (this applies core, bootstrap providers, and the seed composition).

3. **Claim Application**
   - Upload the remote kubeconfig: `kubectl create secret generic cnoe-kubeconfig -n crossplane-system --from-file=kubeconfig=private/kubeconfig`.
   - `kubectl apply -f private/seed-infrastructure-claim.yaml`.

4. **Monitor Progress**
   - Seed status: `kubectl get seedinfrastructureclaims.platform.livewyer.io -o wide` and `...seedinfrastructures...`.
   - Providers: `kubectl -n crossplane-system get pods` and `kubectl get providers.pkg.crossplane.io`.
   - Azure objects: `kubectl get userassignedidentities.managedidentity.azure.upbound.io`, `kubectl get roleassignments.authorization.azure.upbound.io`, `kubectl get dnsarecord.network.azure.upbound.io`, `kubectl get vault.keyvault.azure.upbound.io`.
   - Remote addons: `kubectl --kubeconfig=private/kubeconfig -n argocd get applications`, `kubectl --kubeconfig=private/kubeconfig -n external-secrets get externalsecret`.

5. **Post-Install Smoke Checks**
   - Verify ExternalSecrets are `SecretSynced` and Keycloak/Backstage/Argo Workflows pods are Healthy.
   - Confirm Key Vault secrets exist and Argo CD dashboard lists all applications.

## Cleanup Checklist
1. **Delete Claim First**
   - `kubectl delete seedinfrastructureclaim.platform.livewyer.io/seed-default`.
   - Watch until `kubectl get seedinfrastructures.platform.livewyer.io` returns no items.

2. **Azure Resource Finalization**
   - Crossplane should delete associated identities/role assignments/DNS/Key Vault. If a resource existed prior to the run, delete or import it manually in Azure.

3. **Remote Namespace Reset**
   - On AKS: delete addon namespaces **after** the claim is gone. If termination stalls, remove leftover Argo CD hook resources (`argocd-redis-secret-init` job/role/serviceaccount) or managed Crossplane objects (`workloadidentity`, `object.kubernetes`) to clear finalizers—only after confirming the claim has been deleted.

4. **Provider Cleanup**
   - Delete provider packages (`kubectl delete provider.pkg.crossplane.io/...`) before removing the Crossplane deployments to avoid orphan pods.

5. **Crossplane Core Removal**
   - Once providers are gone, delete `seed/seed/20-seed-composition.yaml` and `seed`.

## Preflight Rules
- Start only when the seed and remote clusters contain no leftover Crossplane/Argo CD resources.
- Ensure the previous remote Crossplane release is removed (or healthy and idle) before applying a new claim.
- Azure must not contain the managed identities, DNS records, or Key Vault expected in the claim unless you import them first.
- Ensure the kubeconfig secret matches the remote cluster to avoid provider-helm/kubernetes failures.
- Do not apply manifests directly to the remote AKS cluster; all changes must flow through the seed claim/composition.

## Observability Shortcuts
- `kubectl describe seedinfrastructure <name>` for detailed composition errors.
- `kubectl logs -n crossplane-system deployment/provider-azure-...` for Azure provider errors.
- `kubectl --kubeconfig=private/kubeconfig -n argocd get applicationsets` to confirm ApplicationSets exist.
