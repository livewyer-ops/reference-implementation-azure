# Crossplane-Driven Seed Deployment Tasks

## Objective
Deploy the CNOE reference implementation to the remote AKS cluster using only the `SeedInfrastructure` claim so that Argo CD and the supporting AppSet are installed via Crossplane `provider-helm` releases.

## Task 1 – Claim Inputs Audit
- Ensure `seed/seed-infrastructure-claim.yaml.example` exposes every field required by Argo CD and the AppSet (repo URL/revision/basepath, GitHub app credentials, cluster/domain metadata, subscription, Key Vault, etc.).
- Extend the claim schema to include any missing parameters; the claim must become the single user-edited file.

## Task 2 – Secrets Derived from Claim
- ✅ Update the `SeedInfrastructure` composition to render all static secrets from the claim parameters:
  - `crossplane-system/cnoe-config` (JSON payload of claim settings).
  - `argocd/cnoe` cluster secret with annotations mirroring the previous Helmfile flow.
  - `argocd/github-app-org` repo credential secret populated from claim fields.
  - `crossplane-system/provider-azure` and any other Crossplane provider secrets needed by downstream releases.
- Confirm no additional config files or templates are required once these secrets are composed.

## Task 3 – Helm Releases via Crossplane
- ✅ Add an Argo CD `Release` (chart `argo-cd`, version `8.0.14`) driven by the claim’s values (ingress host, namespaces, etc.).
- ✅ Add a second `Release` for the AppSet chart sourced from `packages/charts/appset` without modifying existing package content (chart published under `charts/`).
- Wire readiness/dependency ordering so secrets exist before the Helm releases reconcile.

## Task 4 – Composition Wiring & Observability
- Emit useful connection details (Argo CD URL, repo annotations) through composed `connectionDetails`.
- Include explicit dependencies or sync ordering inside the composition to reflect the correct reconciliation flow.
- Validate end-to-end on a KinD seed run that both releases reach `state: deployed` using only the populated claim.

## Task 5 – Bootstrap Script & Documentation
- Keep `bootstrap.sh` minimal (KinD setup, Crossplane install, claim apply); document that the claim is the only file users edit.
- Refresh `README.md`, `AGENTS.md`, and `docs/SEED_MANUAL.md` with the new single-claim workflow, including rotation/troubleshooting guidance for claim-managed secrets and Helm releases.
- Remove references to the Taskfile/Helmfile flow once the Crossplane path reaches parity.
