# Repository Guidelines

## Project Structure & Module Organization
- `Taskfile.yml` still drives the main platform workflows; the seed bootstrap now lives entirely in the `seed/` manifests (Crossplane install bundle, kickoff composition, claim example).
- `config.yaml` holds environment settings validated by `config.schema.yaml`; keep secrets out of git and store real values securely.
- `packages/` houses ArgoCD application bundles (`values.yaml(.gotmpl)` plus manifests), while `templates/` serves Backstage and workflow scaffolder assets; `docs/` supplies reference material and `private/` remains gitignored for kubeconfigs or temporary credentials.

## Seed Workflow Quick Start
1. **Create a clean KinD cluster**
   ```bash
   kind create cluster --config kind.yaml --name seed
   kind get kubeconfig --name seed > private/seed-kubeconfig
   export KUBECONFIG=$(pwd)/private/seed-kubeconfig
   ```
2. **Install Crossplane core**
   ```bash
   kubectl apply -f seed/crossplane-install.yaml
   kubectl wait deployment/crossplane -n crossplane-system --for=condition=Available --timeout=10m
   kubectl wait deployment/crossplane-rbac-manager -n crossplane-system --for=condition=Available --timeout=10m
   ```
3. **Apply the kickoff bundle (providers + composition)**
   ```bash
   kubectl apply -f seed/seed-kickoff.yaml
   ```
4. **Create the remote kubeconfig secret**
   ```bash
   kubectl create secret generic cnoe-kubeconfig \
     -n crossplane-system \
     --from-file=kubeconfig=private/kubeconfig
   ```
5. **Populate and apply the claim**
   ```bash
   cp seed/seed-infrastructure-claim.yaml.example seed/seed-infrastructure-claim.yaml
   ${EDITOR:-vim} seed/seed-infrastructure-claim.yaml   # fill every placeholder (domain, resourceGroup, keyVaultName, location, tenantId, clientId, clientSecret, subscriptionId, clusterName, etc.)
   kubectl apply -f seed/seed-infrastructure-claim.yaml
   ```
6. **Monitor reconciliation**
   ```bash
   kubectl get seedinfrastructureclaims.platform.livewyer.io
   kubectl get dnsarecord.network.azure.upbound.io
   ```
7. **Cleanup**
   ```bash
   kubectl delete seedinfrastructureclaim.platform.livewyer.io/seed-default
   kubectl delete secret azure-service-principal -n crossplane-system || true
   kubectl delete secret cnoe-kubeconfig -n crossplane-system || true
   kind delete cluster --name seed
   rm -f private/seed-kubeconfig seed/seed-infrastructure-claim.yaml
   ```

## Build, Test, and Development Commands
- `task init` checks CLI dependencies and runs `helmfile lint`/`build`; run it after cloning or updating tooling.
- `task install` bootstraps Azure workload identities then applies the platform; use `task sync` for routine updates.
- `task diff` previews Helmfile changes before deployment, and `task update` refreshes Key Vault secrets without applying manifests.

## Coding Style & Naming Conventions
- Format YAML with two-space indentation and keep templated files suffixed `.gotmpl` as in existing packages.
- Name component directories after their chart/application (`packages/backstage`, `packages/ingress-nginx`) so ArgoCD resources stay predictable.
- Validate configuration edits with `yamale -s config.schema.yaml config.yaml` before committing, and prefer lowercase, hyphenated identifiers in manifests unless the schema dictates otherwise.

## Testing Guidelines
- Run `task init` and `task config:lint` ahead of every PR to catch dependency or schema issues early.
- Inspect cluster impact with `task diff`, and render targeted releases via `task helmfile:template -- <release>` when modifying templates.
- Spin up `kind create cluster --config kind.yaml` for local smoke tests when AKS access is limited.

## Commit & Pull Request Guidelines
- Follow conventional commits (`feat:`, `chore:`, `docs:`) consistent with the current history.
- PRs should summarize intent, list touched tasks/config, and link issues; attach screenshots for Backstage UX changes when relevant.
- Keep secrets and temporary overrides out of git and document any manual Azure steps reviewers must reproduce.

## Security & Configuration Tips
- Do not commit populated `config.yaml`; push real values to Key Vault with `task update:secret`.
- Keep `private/` clean—remove kubeconfigs and generated secrets after runs, keep `AZURE_CLIENT_SECRET` out of disk (provide via env), and rotate demo identities with the Azure helper tasks when recycling environments.
- After every seed run, delete the generated `azure-service-principal` and `cnoe-kubeconfig` secrets from `crossplane-system`; recreate the kubeconfig secret whenever cluster credentials rotate.
