# Current Tasks

> Historical revisions are stored in `docs/archive/TASKS.md`.

## Task 1 – Validate Seed Bootstrap Parity ☐
- Run `hack/deployment.sh` on a clean KinD cluster and confirm the claim reaches `Ready=True`.
- Verify bootstrap Azure resources match the legacy Taskfile output (identities, role assignments, DNS wildcard, Key Vault secret).
- Check seed-side providers (`kubectl --kubeconfig=private/seed-kubeconfig get providers.pkg.crossplane.io`) for `Healthy=True` revisions.

## Task 2 – Confirm Remote Crossplane Health ☐
- Ensure Argo CD installs the remote Crossplane release and that controller pods become ready.
- Reconcile provider packages via `hack/reconcile.sh`; confirm remote `providerrevisions.pkg.crossplane.io` are healthy and CRDs (`*.azure.m.upbound.io`) exist.
- Capture any drift from the origin/v2 Taskfile flow and raise follow-up issues if parity cannot be achieved.

## Task 3 – Restore Secret Propagation ☐
- Validate the `azure-keyvault` `ClusterSecretStore` and ExternalSecrets reach `SecretSynced=True` after bootstrap.
- Confirm GitHub credentials and service tokens appear in target namespaces (`github-app-org`, Backstage config, External DNS secret).
- Troubleshoot within the seed composition or helper scripts; packages/ must remain aligned with `origin/v2`.

## Task 4 – Harden Automation & Observability ☐
- Add guardrails/tests to the helper scripts (deployment, reconcile, reset) so they fail fast when prerequisites are missing.
- Extend runbooks with verification checklists and azure cleanup guidance; document how to toggle `AZ_PRESERVE_KEYVAULT` and other flags.
- Track outstanding gaps or defects in this task list to keep parity work visible.
