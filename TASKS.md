# Current Tasks

> Historical revisions are stored in `docs/archive/TASKS.md`.

## Task 1 – Ship UXP Seed Baseline ☑
- Seed now installs the full UXP 2.0.2-up.4 stack (Crossplane, controller-manager, Apollo, WebUI) and the claim reconciles to `Ready=True`.
- Azure bootstrap artefacts and the Key Vault `config` secret are created automatically; the new vault `Secret` resource landed successfully.
- Keep running `hack/deployment.sh`/`hack/reconcile.sh` after edits to guard against regressions.

## Task 2 – Repair Remote Provider Dependencies ☐
- Remote provider revisions (`upbound-provider-azure-*` v2.0.0) stay `Healthy=False` with `missing dependencies: "provider-family-azure" (>=v2)` even though the family package exists—investigate Argo CD sync state and make sure the family provider is not stuck terminating.
- Confirm the remote DeploymentRuntimeConfig matches UXP expectations (service account, workload identity annotations).
- Do not `kubectl apply` live resources; reconcile through Git/Argo so the control plane stays declarative.

## Task 3 – Restore Remote Secrets & Apps ☐
- `ClusterSecretStore/azure-keyvault` reports `InvalidProviderConfig` because the Azure providers are unhealthy—retest after Task 2 and ensure the store becomes `Ready=True`.
- Once secrets flow, recheck ExternalSecrets (`github-app-org`, `hub-cluster-secret`, `external-dns-azure`) and Argo CD applications; today several are `OutOfSync/Degraded`.
- Expect to rerun `hack/reconcile.sh` + Argo resync after the provider dependency issue is fixed.

## Task 4 – Harden Automation & Observability ☐
- Add guardrails/tests to the helper scripts (deployment, reconcile, reset) so they fail fast when prerequisites are missing.
- Extend runbooks with verification checklists and azure cleanup guidance; document how to toggle `AZ_PRESERVE_KEYVAULT` and other flags.
- Track outstanding gaps or defects in this task list to keep parity work visible.
