# Manual Seed Bootstrapping

This runbook describes how to execute the seed phase without relying on the local Taskfile targets. It assumes you have already populated `config.yaml` and obtained an Azure service principal capable of interacting with the target subscription.

> Shortcut: run `./bootstrap.sh` (optionally overriding `REMOTE_KUBECONFIG` or `CLUSTER_CONNECTION_SECRET_NAME`) to execute the steps below as a single flow.

> :warning: The Azure client secret and generated JSON file should **never** be committed. Store them securely and delete the temporary files as soon as the run completes.

> Prefer the commands below. You only need to edit the example claim and then run
> `kubectl apply -f seed/` – no shell script required.

## 1. Bring up the ephemeral KinD cluster

```bash
kind create cluster --config kind.yaml --name seed
export KUBECONFIG=$(pwd)/private/seed-kubeconfig
```

## 2. Prepare runtime configuration

Copy the example claim and fill in all required values (no base64 needed because the
composition takes care of the secret generation):

```bash
cp seed/seed-infrastructure-claim.yaml.example seed/seed-infrastructure-claim.yaml
${EDITOR:-vim} seed/seed-infrastructure-claim.yaml
```

Replace every placeholder (`domain`, `resourceGroup`, `keyVaultName`, `location`, `tenantId`,
`clientId`, `subscriptionId`, `clientSecret`, `clusterName`, etc.). **Keep this file local – it
contains credentials.**

## 3. Apply the seed manifest and wait for bootstrap

Apply the directory and wait for the Crossplane deployments to become available (the composition will create the `azure-service-principal` secret automatically):

```bash
kubectl apply -f seed/
kubectl wait deployment/crossplane -n crossplane-system --for=condition=Available --timeout=10m
kubectl wait deployment/crossplane-rbac-manager -n crossplane-system --for=condition=Available --timeout=10m
```

The kickoff manifest installs Crossplane v2.0.2 (via the official Helm chart), pins the Azure and Helm providers,
and renders the `SeedInfrastructure` composition.

### 4. Create the remote kubeconfig secret

The composition expects the remote AKS kubeconfig to be available as a secret in `crossplane-system`.
Populate it from the kubeconfig you retrieved when preparing the environment:

```bash
kubectl create secret generic cnoe-kubeconfig \
  -n crossplane-system \
  --from-file=kubeconfig=private/kubeconfig
```

### 5. Create the SeedInfrastructure claim

Copy the sample claim, update it with your environment values (Azure identifiers, Git repo metadata, GitHub App credentials, ApplicationSet chart location, etc.), and apply it:

```bash
cp seed/seed-infrastructure-claim.yaml.example seed/seed-infrastructure-claim.yaml
${EDITOR:-vim} seed/seed-infrastructure-claim.yaml  # fill each parameter (Azure IDs, repo settings, GitHub App values, chart repo, etc.)
- # Publish the ApplicationSet chart somewhere accessible (e.g., `https://raw.githubusercontent.com/<org>/<repo>/<branch>/charts`) and update appsetChartRepository/appsetChartName/appsetChartVersion.
kubectl apply -f seed/seed-infrastructure-claim.yaml
```

Monitor progress:

```bash
kubectl get seedinfrastructureclaims.platform.livewyer.io
kubectl get providerrevision
kubectl get dnsarecord.network.azure.upbound.io
```
The `SeedInfrastructure` claim:
- Stores the service principal credentials in `crossplane-system/azure-service-principal`.
- Creates or reconciles the Key Vault and wildcard DNS record in Azure.
- Points the `remote-aks` (Helm provider) configuration at the kubeconfig secret you created manually and installs the Argo CD + ApplicationSet Helm releases, which in turn render the addon `ApplicationSet` resources from your Git repo.

## 5. Clean up

```bash
kubectl delete secret azure-service-principal -n crossplane-system || true
kubectl delete secret cnoe-kubeconfig -n crossplane-system || true
kubectl delete seedinfrastructureclaim.platform.livewyer.io/seed-default || true
rm -f private/seed-kubeconfig seed/seed-infrastructure-claim.yaml
kind delete cluster --name seed
```

Re-create the kubeconfig secret whenever you rotate cluster credentials. Ensure any Azure client secrets created for this run are rotated or invalidated according to your security policies.
