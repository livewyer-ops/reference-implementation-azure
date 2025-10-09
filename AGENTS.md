# Repository Guidelines

## Project Structure & Module Organization
- `Taskfile.yml` orchestrates install, diff, and sync workflows (see `docs/TASKFILE.md` for details).
- `config.yaml` holds environment settings validated by `config.schema.yaml`; keep secrets out of git and store real values securely.
- `packages/` houses ArgoCD application bundles (`values.yaml(.gotmpl)` plus manifests), while `templates/` serves Backstage and workflow scaffolder assets; `docs/` supplies reference material and `private/` remains gitignored for kubeconfigs or temporary credentials.

## Build, Test, and Development Commands
- `task init` checks CLI dependencies and runs `helmfile lint`/`build`; run it after cloning or updating tooling.
- `task install` bootstraps Azure workload identities then applies the platform; use `task sync` for routine updates.
- `task diff` previews Helmfile changes before deployment, and `task update` refreshes Key Vault secrets without applying manifests.
- The seed bootstrap now relies on manual `kind`/`kubectl` commands; follow the quick reference below or `docs/SEED_MANUAL.md`.

- `kind create cluster --config kind.yaml --name seed`
- `export KUBECONFIG=$(pwd)/private/seed-kubeconfig`
- Copy `seed/user-secrets.yaml.example` → `seed/user-secrets.yaml`, paste the Azure service-principal JSON under `stringData.credentials`.
- Copy `seed/seed-infrastructure-claim.yaml.example` → `seed/seed-infrastructure-claim.yaml`, fill in domain/resource group/etc.
- `kubectl apply -f seed/` (wait for `crossplane-bootstrap` job to complete).
- `kubectl delete secret azure-service-principal -n crossplane-system` once testing finishes, followed by `kind delete cluster --name seed` and removing `seed/user-secrets.yaml` (and any local credential copies).
- See `docs/SEED_MANUAL.md` for a full walkthrough.

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
