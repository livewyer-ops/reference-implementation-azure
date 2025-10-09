# Repository Guidelines

## Project Structure & Module Organization
- `seed/` contains the rendered Crossplane install (`crossplane-install.yaml`), the provider/composition bundle (`seed-kickoff.yaml`), and the claim template; these are the only manifests that should touch Azure.
- `private/` stays gitignored and stores the live claim (`seed-infrastructure-claim.yaml`), the AKS kubeconfig, and any transient credentials pulled from Azure; **never** commit files in this directory.
- `charts/` hosts the packaged ApplicationSet chart that Argo CD installs on the remote cluster; keep the index in sync with the version referenced by the claim.
- `packages/` holds the Argo CD application values that end up in the ApplicationSet chart. Avoid editing these unless the addon itself needs different Helm inputs.
- `docs/` carries operator-facing runbooks (e.g. `SEED_MANUAL.md`) and diagrams; keep them aligned with the Crossplane flow.

## Seed Workflow Cheat Sheet
1. **Create the seed KinD cluster**
   ```bash
   kind delete cluster --name seed || true
   kind create cluster --config kind.yaml --name seed
   kind get kubeconfig --name seed > private/seed-kubeconfig
   export KUBECONFIG=$(pwd)/private/seed-kubeconfig
   ```
2. **Populate claim inputs**
   ```bash
   cp seed/seed-infrastructure-claim.yaml.example private/seed-infrastructure-claim.yaml
   ${EDITOR:-vim} private/seed-infrastructure-claim.yaml   # fill clientId/clientSecret/clientObjectId, domain, repo, etc.
   ```
   `clientObjectId` is the object ID of the Azure service principal; Crossplane now assigns this principal the Key Vault Administrator role automatically.
3. **Create the remote kubeconfig secret**
   ```bash
   kubectl create secret generic cnoe-kubeconfig \
     -n crossplane-system \
     --from-file=kubeconfig=private/kubeconfig
   ```
4. **Apply the Crossplane stack and claim**
   ```bash
   kubectl apply -f seed/crossplane-install.yaml
   kubectl wait deployment/crossplane -n crossplane-system --for=condition=Available --timeout=10m
   kubectl wait deployment/crossplane-rbac-manager -n crossplane-system --for=condition=Available --timeout=10m
   kubectl apply -f seed/seed-kickoff.yaml
   kubectl apply -f private/seed-infrastructure-claim.yaml
   ```
5. **Monitor reconciliation**
   ```bash
   kubectl get seedinfrastructureclaims.platform.livewyer.io
   kubectl get roleassignments.authorization.azure.upbound.io
   kubectl get secrets.keyvault.azure.upbound.io
   kubectl get releases.helm.crossplane.io
   kubectl --kubeconfig=private/kubeconfig -n argocd get applications
   ```
6. **Cleanup**
   ```bash
   kubectl delete seedinfrastructureclaim.platform.livewyer.io/seed-default || true
   kubectl delete secret azure-service-principal -n crossplane-system || true
   kubectl delete secret cnoe-kubeconfig -n crossplane-system || true
   kind delete cluster --name seed
   rm -f private/seed-kubeconfig private/seed-infrastructure-claim.yaml
   ```

## Current State & Hot Spots
- `seed-default` is `Ready=True`; Azure identities, role assignments (including the bootstrap service principal), Key Vault, and DNS wildcard are all provisioned via Crossplane.
- The `keyvault-config` secret now syncs from the rendered `cnoe-config` secret—updates propagate without a helper script.
- Remote AKS status:
- `external-dns` pod crash-loops because the chart still expects `/etc/kubernetes/azure.json`. The ExternalSecret now exists, but the generated ClusterSecretStore still references the old `cnoe-ref-impl` vault URL—update it to the live Key Vault so the secret materialises.
  - `backstage` crash-loops with `backend.baseUrl` missing (config secret not yet sourced into the namespace).
  - `cert-manager` repeatedly flips between `Synced`/`OutOfSync` but eventually reports Healthy after each automated retry.
- Use `kubectl --kubeconfig=private/kubeconfig` for remote diagnostics; Argo CD exposes rich status via `kubectl -n argocd get application <name> -o json`.

## Build, Test, and Development Commands
- `kubectl apply -f seed/seed-kickoff.yaml` and `kubectl apply -f private/seed-infrastructure-claim.yaml` are the primary iteration levers.
- `kubectl get seedinfrastructure* -o json | jq` surfaces Crossplane conditions when iterating on the composition.
- Remote checks:
  ```bash
  kubectl --kubeconfig=private/kubeconfig -n argocd get applications
  kubectl --kubeconfig=private/kubeconfig -n external-dns logs -l app.kubernetes.io/name=external-dns
  ```
- Wrap longer troubleshooting commands in scripts if repeatable, but keep entry points to ≤4 commands per the rules.

## Coding Style & Naming Conventions
- YAML → 2-space indentation, lowercase resource names, keep composition resource names stable (`roleAssignmentCrossplane`, etc.) for easier debugging.
- Prefer descriptive parameter names inside the claim (`clientObjectId`, `clusterOidcIssuerUrl`) so Crossplane patches remain readable.
- When updating Go-template’d values in `charts/` or `packages/`, add concise comments only where logic isn’t obvious.

## Testing Guidelines
- For composition updates: reapply `seed/seed-kickoff.yaml`, reapply the claim, and watch `kubectl get seedinfrastructures.platform.livewyer.io -o json | jq '.status.conditions'`.
- Validate Azure side-effects by listing the managed resources Crossplane creates (`kubectl get userassignedidentities.managedidentity.azure.upbound.io` etc.).
- For AKS addons, rely on Argo CD application health plus pod logs (`kubectl --kubeconfig=private/kubeconfig -n <ns> get pods`).
- When external-dns/backstage issues are resolved, re-run the entire seed flow from a fresh KinD cluster to catch regressions.

## Commit & Pull Request Guidelines
- Stick with conventional commits (`feat:`, `fix:`, `chore:`). Reference TASKS.md items or open issues when applicable.
- Summarise Crossplane/AKS impacts in the PR body, including any manual follow-up steps reviewers need (e.g. “reapply claim”).
- Include screenshots or command output snippets only when they add value; redact domains or IDs tied to the tenant.

## Security & Configuration Tips
- Keep `private/seed-infrastructure-claim.yaml`, `private/kubeconfig`, and any downloaded Azure material out of git—remove them after each run.
- Rotate the Azure client secret and update both `clientSecret` and `clientObjectId` in the claim whenever the service principal is regenerated.
- Delete the `azure-service-principal` and `cnoe-kubeconfig` secrets in `crossplane-system` when finished, and tear down the KinD cluster to avoid drift.
