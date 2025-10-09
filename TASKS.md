# Local Seed Migration Tasks

## Objective
Replace the current Azure CLI + Helm-based seed phase with an ephemeral local Kubernetes cluster that reconciles the same Azure infrastructure and Helm releases through Crossplane, driven entirely by declarative manifests (`kubectl apply -f seed/`).

- **Current state**
  - Seed bootstrap is executed manually using `kind` + `kubectl`; see quick steps in `docs/SEED_MANUAL.md`.
  - Only declarative manifests remain in `seed/` (Crossplane install bundle, composition, claim example).
  - Operators manually create the `crossplane-system/<clusterConnectionSecretName>` (default `cnoe-kubeconfig`) secret from the remote AKS kubeconfig before applying the claim.

## Preconditions
- Document current seed actions in `Taskfile.yml` (Azure resource creation, Helmfile invocations, secret handling).
- Confirm access to build/publish container images inside the organisation registry.
- Capture credentials for the remote AKS target cluster and supporting Azure identities (service principals, managed identities, Key Vault secrets).
- Ensure `task update:kubeconfig` (or equivalent) has been executed so `private/kubeconfig` exists before observing the real cluster.
- Provide an Azure service principal (clientId/clientSecret/etc.) via `seed/seed-infrastructure-claim.yaml` before applying the seed manifests (do not commit the populated file).

## Task Group 1 – Seed Container Image
1. Define container requirements (kubectl, helmfile, crossplane CLI, Azure CLI?, yq/jq, helm plugins).
2. Create Dockerfile that installs tooling, configures non-root user, and embeds scripts to create the local seed cluster.
3. Implement entrypoint to:
   - Create the local cluster (KinD or K3s) and export kubeconfig.
   - Apply the static kickoff manifest (installs Crossplane + packages via Job) and optionally block for completion.
4. Automate image build/push pipeline (Taskfile target + CI job).

## Task Group 1A – Transition Away from Taskfile
1. Confirm all documentation references the manual commands:
   - `kind create cluster --config kind.yaml --name seed`.
   - `export KUBECONFIG=$(pwd)/private/seed-kubeconfig` (or set via tooling).
   - Copy/edit `seed/seed-infrastructure-claim.yaml.example` (fill every placeholder, including clientSecret).
   - `kubectl apply -f seed/` followed by `kubectl wait deployment/crossplane -n crossplane-system --for=condition=Available --timeout=10m`.
2. Validate that no CI or docs still reference removed `task seed:*` targets.

## Task Group 2 – Ephemeral Local Cluster Bootstrap
1. Select local distro (KinD preferred) and capture cluster config (node labels, storage).
2. Write script/Taskfile target to spin up/down the cluster for each run.
3. Ensure kubeconfig is mounted into container and exported for Crossplane installation.

## Task Group 3 – Crossplane Core Setup
1. Package Crossplane helm install into bootstrap manifest (`ProviderConfig` namespace, RBAC).
2. Install Crossplane providers:
   - `provider-jet-azure` (or successor) for Azure resources.
   - `provider-helm` for remote chart deployments.
3. Configure provider credentials via Kubernetes Secrets referenced in `ProviderConfig` objects.

## Task Group 4 – Azure Resource Reconciliation
1. Inventory all `az` commands in the seed tasks (managed identities, key vault, DNS, etc.).
2. Map each resource to Crossplane managed resources or compositions; document gaps.
3. Author Crossplane `CompositeResourceDefinitions`/`Compositions` to encapsulate required Azure objects.
4. Create parameter definitions for values currently sourced from `config.yaml`.
5. Implement dependency ordering using `DependsOn` or composition topology.

## Task Group 5 – Helm Release Migration
1. Translate Helmfile releases into `HelmRelease` managed resources via `provider-helm`.
2. Externalize chart values from existing `packages/*/values.yaml` into Crossplane-friendly secrets/configmaps.
3. Define connection secrets for each release (URLs, credentials) for later Taskfile consumption.

## Task Group 6 – Remote Cluster Credential Injection
1. ✅ Documented manual step to create the kubeconfig secret prior to applying the claim.
2. Capture troubleshooting guidance for stale or missing kubeconfig secrets (e.g., how to rebuild from `private/kubeconfig`).
3. Document the rotation flow for the service-principal secret and the kubeconfig secret (delete + recreate secret, re-apply claim).
4. Confirm Helm provider connectivity against a real AKS cluster once workloads are deployed.

## Task Group 7 – Single Manifest Assembly
1. Create `seed-kickoff.yaml` aggregating:
   - Namespace scaffolding.
   - Crossplane installation (Helm chart rendered to YAML).
   - Provider packages, secrets, compositions, and claims.
   - Any CRDs required for compositions.
2. Document ordering/health checks for reconciliation before destroying the local cluster (e.g., wait for the bootstrap job, confirm providers are healthy).

## Task Group 8 – Integration & Cleanup
1. Update documentation, onboarding scripts, and pipelines to call the manual seed commands directly.
2. Provide optional helper scripts or containers (e.g., `seed/Dockerfile`) while keeping them detached from Taskfile.
3. Ensure manual cleanup guidance (delete secrets, remove KinD cluster) is consistently communicated.

## Task Group 10 – Remaining Follow-up
1. Validate the new pipeline-based Composition (`seed-infrastructure`) against real AKS environments and capture any additional requirements (permissions, managed identity scopes). 🔄
2. Document day-2 operations for the claim (updating parameters, deleting resources) and integrate with platform runbooks. 🔄
3. Manual flow documented; review whether further automation is required. ✅

## Task Group 9 – Validation
1. Create acceptance checklist verifying Azure resources and Helm releases match prior implementation.
2. Add smoke tests executed inside container (e.g., `helm status`, `az resource show` via Crossplane outputs).
3. Run regression against staging AKS cluster; capture timing and failure modes.

## Current Outstanding Tasks
- Expand documentation/runbooks with troubleshooting steps for missing/incorrect kubeconfig secrets (how to regenerate, expected secret structure).
- Define and automate (where possible) the rotation process for both the Azure service principal and the kubeconfig secret.
- Explore future Crossplane provider improvements that would allow read-only kubeconfig retrieval without manual secrets.
