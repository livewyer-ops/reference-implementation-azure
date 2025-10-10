# Seed / Remote Split Tasks

## Task 1 – Remote Crossplane Reinstatement ☐
- Add a dedicated release (via Argo CD/ApplicationSet) that installs Crossplane into the remote AKS cluster, mirroring the legacy Helmfile chart with no behavioural drift.
- Ensure the remote release wires in `packages/crossplane/kustomize/` and `packages/crossplane/manifests/` so provider bundles run in AKS exactly as they did on the `v2` branch.
- Verify remote Crossplane receives workload-identity annotations and can authenticate to Azure without requiring new manual steps.

## Task 2 – Seed Bootstrap Composition Refinement ☐
- Trim `seed/20-seed-composition.yaml` so the seed control plane creates Azure prerequisites and installs Argo CD + remote Crossplane only—the same duties formerly executed by Taskfile `az` commands and Helmfile.
- Keep bootstrap Azure providers on the seed cluster; avoid managing addon namespaces or workloads from the seed claim so the remote cluster remains untouched.
- Update the claim/parameters to pass any data the remote Crossplane release needs (e.g., bootstrap secrets) while keeping addon configuration in line with the legacy workflow.

## Task 3 – Cleanup & Finalizer Automation ☐
- Provide scripts or composition hooks to remove Argo CD hook jobs/roles/service accounts once the claim is deleted, preserving parity with the Helmfile teardown expectations.
- Automate removal of Crossplane-managed objects (workload identities, object.kubernetes) that block namespace deletion so the new bootstrap remains reversible.
- Document the teardown order for both control planes so resets stay deterministic and aligned with the historical process.

## Task 4 – Observability & Smoke Tests ☐
- Create a verification checklist that covers seed Crossplane status, remote Crossplane providers, and addon health, highlighting equivalence with the `v2` workflow.
- Add basic smoke tests (ExternalSecrets, Keycloak, Backstage, Argo Workflows) executed after each bootstrap to prove the new process yields the same platform state.
- Capture troubleshooting pointers for both control planes in `DESIGN.md` or a runbook, emphasising where behaviour now differs (or intentionally matches) the legacy model.
