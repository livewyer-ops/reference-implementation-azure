# Manual Seed Bootstrapping

This runbook describes how to execute the seed phase without relying on the local Taskfile targets. It assumes you have already populated `config.yaml`, run `task update:kubeconfig` (or equivalent) to create `private/kubeconfig`, and obtained an Azure client secret capable of provisioning the managed resources.

> :warning: The Azure client secret and generated JSON file should **never** be committed. Store them securely and delete the temporary files as soon as the run completes.

> Prefer the commands below. You only need to edit the two example manifests and then run
> `kubectl apply -f seed/` – no shell script required.

## 1. Bring up the ephemeral KinD cluster

```bash
kind create cluster --config kind.yaml --name seed
export KUBECONFIG=$(pwd)/private/seed-kubeconfig
```

## 2. Prepare runtime configuration

Copy the example secrets manifest and paste the required values (no base64 needed because
it uses `stringData`):

```bash
cp seed/user-secrets.yaml.example seed/user-secrets.yaml
${EDITOR:-vim} seed/user-secrets.yaml
```

Populate `stringData.credentials` with the Azure service principal JSON that has access to
your subscription. Delete `seed/user-secrets.yaml` when you are finished.

## 3. Create required secrets inside the seed cluster

If the secrets already exist in the remote cluster they will be reused. Otherwise they will
be created when you run `kubectl apply -f seed/` in the next step.

## 4. Apply the seed manifest and wait for bootstrap

Make sure `seed/user-secrets.yaml` (and optionally `seed/seed-infrastructure-claim.yaml`) are
present, then apply the directory:

```bash
kubectl apply -f seed/
kubectl wait job/crossplane-bootstrap \
  --namespace seed-system \
  --for=condition=Complete \
  --timeout=15m
```

The kickoff manifest installs Crossplane v2.0.2 (via the official Helm chart) and
pins `provider-azure` to `xpkg.upbound.io/upbound/provider-azure:v0.30.0`. Later
provider builds currently ship CRDs that violate Crossplane's naming validation,
so v0.30.0 is the newest tag that passes health checks on Kubernetes 1.30.

### 4a. Create the SeedInfrastructure claim

Once the bootstrap job completes and the providers/functions are healthy, copy the
sample claim, update it with your environment values (matching `config.yaml`), and
apply it:

```bash
cp seed/seed-infrastructure-claim.yaml.example seed/seed-infrastructure-claim.yaml
${EDITOR:-vim} seed/seed-infrastructure-claim.yaml
kubectl apply -f seed/seed-infrastructure-claim.yaml
```

Monitor progress:

```bash
kubectl get seedinfrastructureclaims.platform.livewyer.io
kubectl get managed -n crossplane-system
```

The `seed-kickoff.yaml` manifest installs Crossplane v1.15, the Azure and Helm providers, and leaves a placeholder for compositions/claims. Customise the following files before applying if required:

- `seed/seed-kickoff.yaml` – high-level configuration and bootstrap job.
- `seed/seed-kickoff.yaml` (ConfigMap data: `providers.yaml`, `providerconfigs.yaml`, `compositions.yaml`) – extend for compositions and managed resources.

## 5. Clean up

```bash
kubectl delete secret azure-service-principal -n crossplane-system
rm -f private/seed-kubeconfig seed/user-secrets.yaml
kind delete cluster --name seed
```

Ensure any Azure client secrets created for this run are rotated or invalidated according to your security policies.

### Optional helper

To avoid tamping secrets directly on the command line, copy the example manifests:

```bash
cp seed/user-secrets.example.yaml seed/user-secrets.yaml
cp seed/seed-infrastructure-claim.yaml.example seed/seed-infrastructure-claim.yaml
```

Edit the copies, then apply the entire directory:

```bash
kubectl apply -f seed/
```
