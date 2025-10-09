![overview](docs/images/overview.png)

> **_NOTE:_** Applications deployed in this repository are not meant or configured for production.

<!-- omit from toc -->
# CNOE Azure Reference Implementation

This repository provides a reference implementation for deploying Cloud Native Operations Enabler (CNOE) components on Azure Kubernetes Service (AKS) using GitOps principles.

<!-- omit from toc -->
## Table of Contents

- [Architecture](#architecture)
  - [Deployed Components](#deployed-components)
- [Important Notes](#important-notes)
- [Prerequisites](#prerequisites)
  - [Required Azure Resources](#required-azure-resources)
    - [Setup Guidance for Azure Resources](#setup-guidance-for-azure-resources)
  - [GitHub Integration Setup](#github-integration-setup)
    - [Create GitHub App for Backstage](#create-github-app-for-backstage)
    - [Create GitHub Token](#create-github-token)
- [Installation Flow](#installation-flow)
- [Security Notes](#security-notes)
- [Installation Steps](#installation-steps)
  - [Installation Requirements](#installation-requirements)
  - [1. Configure the Installation](#1-configure-the-installation)
    - [DNS and TLS Configuration](#dns-and-tls-configuration)
      - [Automatic (Recommended)](#automatic-recommended)
      - [Manual](#manual)
  - [2. Install Components](#2-install-components)
  - [3. Monitor Installation](#3-monitor-installation)
  - [4. Get Access URLs](#4-get-access-urls)
  - [5. Access Backstage](#5-access-backstage)
- [Usage](#usage)
- [Update Component Configurations](#update-component-configurations)
  - [Backstage Templates](#backstage-templates)
- [Uninstall](#uninstall)
- [Contributing](#contributing)
- [Troubleshooting](#troubleshooting)
- [Potential Enhancements](#potential-enhancements)
- [Manual Seed Bootstrap](#manual-seed-bootstrap)

## Architecture

- The seed phase is orchestrated by **Crossplane** using a reusable composition (`seed/seed-kickoff.yaml`) and a single claim (`private/seed-infrastructure-claim.yaml`).
- Components are deployed as **ArgoCD Applications**
- Uses **Azure Workload Identity** for secure authentication to Azure services
- Files under the `/packages` directory are meant to be usable without modifications
- Platform configuration is rendered from the claim into the `cnoe-config` secret (and mirrored to Key Vault) rather than editing `config.yaml` directly.

## How It Works

- `seed/crossplane-install.yaml` installs the Crossplane core controllers (same output as the official Helm chart, rendered once for reuse).
- `seed/seed-kickoff.yaml` declares the supporting primitives: provider packages (Azure & Helm), the patch-and-transform function, a small RBAC bundle, and the pipeline-based composition (`SeedInfrastructure`) that wires those pieces together.
- Copy `seed/seed-infrastructure-claim.yaml.example` to `private/seed-infrastructure-claim.yaml`, then fill in the Azure-specific values (domain, resource group, subscription, tenant, workload-identity IDs, **clientObjectId**, client secret, etc.). Set `repoRevision` to the branch that hosts your packaged manifests (for this branch we use `v2-seeding-codex`). Applying the claim generates the Azure service-principal secret, assigns the service principal Key Vault permissions, and renders all composed resources automatically.
- The complete bootstrap sequence is therefore:
  ```bash
  kind create cluster --config kind.yaml --name seed
  kind get kubeconfig --name seed > private/seed-kubeconfig
  export KUBECONFIG=$(pwd)/private/seed-kubeconfig
  kubectl apply -f seed/crossplane-install.yaml
  kubectl wait deployment/crossplane -n crossplane-system --for=condition=Available --timeout=10m
  kubectl wait deployment/crossplane-rbac-manager -n crossplane-system --for=condition=Available --timeout=10m
  kubectl create secret generic cnoe-kubeconfig -n crossplane-system --from-file=kubeconfig=private/kubeconfig
  kubectl apply -f seed/seed-kickoff.yaml
  kubectl apply -f private/seed-infrastructure-claim.yaml   # populated from the example template
  ```
- Crossplane then reconciles the Azure-facing resources (service-principal secret, Key Vault + secret, wildcard DNS record, role assignments) and installs Argo CD plus the ApplicationSet controller via `provider-helm` releases. The published ApplicationSet chart (see `charts/`) renders the full suite of addon ApplicationSets, driven entirely by the claim parameters (Azure IDs, repo metadata, routing flags, GitHub App credentials).
- Provide an accessible Helm repository for the ApplicationSet chart (set `appsetChartRepository`, `appsetChartName`, and `appsetChartVersion` in the claim). This can point to an OCI registry or a static chart archive you publish.
- The Helm provider expects the remote AKS kubeconfig to be available in `crossplane-system/<clusterConnectionSecretName>`; create this secret manually from the existing kubeconfig before applying the claim.
- Track progress with:
  ```bash
  kubectl get seedinfrastructureclaims.platform.livewyer.io
  kubectl get dnsarecord.network.azure.upbound.io
  kubectl get roleassignments.authorization.azure.upbound.io
  kubectl get secrets.keyvault.azure.upbound.io
  ```

### Deployed Components

| Component        | Version    | Purpose                        |
| ---------------- | ---------- | ------------------------------ |
| ArgoCD           | 8.0.14     | GitOps continuous deployment   |
| Crossplane       | 2.0.2-up.4 | Infrastructure as Code         |
| Ingress-nginx    | 4.7.0      | Ingress controller             |
| ExternalDNS      | 1.16.1     | Automatic DNS management       |
| External-secrets | 0.17.0     | Secret management              |
| Cert-manager     | 1.17.2     | TLS certificate management     |
| Keycloak         | 24.7.3     | Identity and access management |
| Backstage        | 2.6.0      | Developer portal               |
| Argo-workflows   | 0.45.18    | Workflow orchestration         |

## Important Notes

- **Azure Resource Management**: The seed phase now assumes that only the AKS cluster and its parent DNS zone already exist. Crossplane compositions create or reconcile the supporting pieces (service-principal secret, Key Vault, wildcard DNS record, Helm provider configuration) once you supply those inputs and provide the remote kubeconfig as a Kubernetes secret.
- **Production Readiness**: The helper tasks in this repository are for creating Azure resources for demo purposes only. Any production deployments should follow enterprise infrastructure management practices.
- **Configuration Management**: The claim renders the platform configuration into `cnoe-config` (stored as a Kubernetes secret and mirrored to Key Vault). The `private/` directory is only for temporary files during development and must never be committed.

## Prerequisites

### Required Azure Resources

Before using this reference implementation, you **MUST** have the following Azure resources already created and configured:

1. **AKS Cluster** (1.27+) with:
   - OIDC Issuer enabled (`--enable-oidc-issuer`)
   - Workload Identity enabled (`--enable-workload-identity`)
    - Sufficient node capacity for all components
     - For reference, the legacy helper (`task azure:creds:create`) provisions a node pool sized `standard_d4alds_v6`.
2. **Azure DNS Zone**
   - A registered domain with Azure DNS as the authoritative DNS service
3. **Azure Key Vault**
   - Crossplane will create or reconcile this vault using the name you provide
   - Ensure the service principal in the claim has permissions to manage it
4. **Crossplane Workload Identity**
   - Azure Managed Identity with appropriate permissions
   - Federated credentials configured for the AKS cluster OIDC issuer
5. **Seed Service Principal**
   - Application (client) ID, object ID, and client secret for the Azure AD service principal that Crossplane uses.
   - The object ID (`clientObjectId`) is required so the composition can grant Key Vault RBAC automatically.

> **Important**: 
> - The AKS cluster and DNS zone must live in the same subscription and resource group; the claim uses those identifiers directly.
> - Crossplane can (re)create the Key Vault and wildcard record, but your service principal needs sufficient rights over the subscription/resource group.
> - Helper `task` targets that scaffold Azure resources remain for demos only; rely on your organisation's IaC workflows for persistent environments.

#### Setup Guidance for Azure Resources

For setting up the prerequisite Azure resources, refer to the official Azure documentation:

- [Create an AKS cluster](https://docs.microsoft.com/en-us/azure/aks/kubernetes-walkthrough)
- [Azure DNS zones](https://docs.microsoft.com/en-us/azure/dns/)
- [Azure Key Vault](https://docs.microsoft.com/en-us/azure/key-vault/)
- [Azure Workload Identity](https://azure.github.io/azure-workload-identity/)

### GitHub Integration Setup

#### Create GitHub App for Backstage

You need a GitHub App to enable Backstage integration with your GitHub organisation.

**Option 1: Using Backstage CLI (Recommended)**

```bash
npx '@backstage/cli' create-github-app ${GITHUB_ORG_NAME}
# Select appropriate permissions when prompted
# Install the app to your organisation in the browser

# Move the credentials file to a temporary location
mkdir -p private
GITHUB_APP_FILE=$(ls github-app-* | head -n1)
mv ${GITHUB_APP_FILE} private/github-integration.yaml
```

**Option 2: Manual Creation**
Follow [Backstage GitHub App documentation](https://backstage.io/docs/integrations/github/github-apps) and save the credentials as `private/github-integration.yaml`.

> **Note**: The `private/` directory is for temporary files during development/testing only. Persisted configuration should live in your Crossplane claim (and any Key Vault secrets it renders), not in version-controlled private files.

#### Create GitHub Token

Create a GitHub Personal Access Token with these permissions:

- Repository access for all repositories
- Read-only access to: Administration, Contents, and Metadata

Save the token value temporarily; you will need it when populating the GitHub section of your claim and the `cnoe-config` payload.

## Installation Flow

1. Copy `seed/seed-infrastructure-claim.yaml.example` to `private/seed-infrastructure-claim.yaml` and populate every placeholder (domain, Azure IDs, **clientObjectId**, repo metadata, chart repository).
2. Create a local KinD cluster, apply `seed/crossplane-install.yaml`, then apply `seed/seed-kickoff.yaml` to install the Azure/Helm providers and the composition.
3. Populate the remote AKS kubeconfig secret (`cnoe-kubeconfig`) in `crossplane-system`.
4. Apply `private/seed-infrastructure-claim.yaml`; Crossplane provisions Azure identities, role assignments, Key Vault + secret, and the Helm releases that install Argo CD with the ApplicationSets.
5. Monitor progress with `kubectl get seedinfrastructureclaims.platform.livewyer.io`, `kubectl get roleassignments.authorization.azure.upbound.io`, and `kubectl --kubeconfig=private/kubeconfig -n argocd get applications`.

## Security Notes

- GitHub App credentials contain sensitive information - handle with care
- Configuration secrets are stored in Azure Key Vault
- Workload Identity is used for secure Azure authentication
- TLS encryption is used for all external traffic

## Installation Steps

### Prerequisite Tools

- **Azure CLI** (2.13+) with access to the subscription that hosts AKS/DNS/Key Vault
- **kubectl** (1.27+) and **kind** (if running the seed cluster locally)
- **kubelogin** for AKS authentication
- **helm** (3.x) for chart packaging
- **jq**/ **yq** for inspecting manifests
- A **GitHub Organisation** (free) with a GitHub App configured for Backstage

### 1. Prepare the Installation

1. Copy the claim template and populate every field:
   ```bash
   cp seed/seed-infrastructure-claim.yaml.example private/seed-infrastructure-claim.yaml
   ${EDITOR:-vim} private/seed-infrastructure-claim.yaml
   ```
   Required values include the AKS cluster name, resource group, subscription ID, OIDC issuer URL, DNS domain, Key Vault name, GitHub metadata, and the service principal credentials (`clientId`, `clientObjectId`, `clientSecret`).
2. Publish the ApplicationSet chart (e.g. host the packaged chart + index under `charts/`) and reference it via `appsetChartRepository`, `appsetChartName`, and `appsetChartVersion`.
3. Gather the remote AKS kubeconfig and save it to `private/kubeconfig`; this will become the `cnoe-kubeconfig` secret.

### 2. Bring up the Seed Stack

```bash
kind create cluster --config kind.yaml --name seed
kind get kubeconfig --name seed > private/seed-kubeconfig
export KUBECONFIG=$(pwd)/private/seed-kubeconfig
kubectl apply -f seed/crossplane-install.yaml
kubectl wait deployment/crossplane -n crossplane-system --for=condition=Available --timeout=10m
kubectl wait deployment/crossplane-rbac-manager -n crossplane-system --for=condition=Available --timeout=10m
kubectl apply -f seed/seed-kickoff.yaml
kubectl create secret generic cnoe-kubeconfig -n crossplane-system --from-file=kubeconfig=private/kubeconfig
```

### 3. Apply the Claim

```bash
kubectl apply -f private/seed-infrastructure-claim.yaml
kubectl get seedinfrastructureclaims.platform.livewyer.io
```

### 4. Monitor Installation

- Check composed resources:
  ```bash
  kubectl get roleassignments.authorization.azure.upbound.io
  kubectl get secrets.keyvault.azure.upbound.io
  kubectl get releases.helm.crossplane.io
  ```
- Inspect remote workloads:
  ```bash
  kubectl --kubeconfig=private/kubeconfig -n argocd get applications
  kubectl --kubeconfig=private/kubeconfig -n external-dns logs -l app.kubernetes.io/name=external-dns
  ```
- Port-forward to Argo CD if you need the UI:
  ```bash
  kubectl --kubeconfig=private/kubeconfig -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d
  kubectl --kubeconfig=private/kubeconfig -n argocd port-forward svc/argocd-server 8080:80
  ```

### 5. Access Backstage

Once Keycloak and Backstage report Healthy, retrieve the demo user credentials:

```bash
kubectl --kubeconfig=private/kubeconfig -n keycloak get secret keycloak-config -o yaml | yq '.data.USER1_PASSWORD | @base64d'
```

## Usage

See [DEMO.md](docs/DEMO.md) for information on how to navigate the platform and for usage examples.

## Update Component Configurations
To tweak addon configuration, update the relevant files under `packages/`, rebuild/publish the ApplicationSet chart, bump `appsetChartVersion` in your claim, and reapply the claim (`kubectl apply -f private/seed-infrastructure-claim.yaml`). Argo CD will reconcile the new chart release automatically.

### Backstage Templates

Backstage templates can be found in the `templates/` directory

## Uninstall
Delete the claim to remove all Azure/AKS resources created by Crossplane, then clean up the seed cluster.

```bash
kubectl delete seedinfrastructureclaim.platform.livewyer.io/seed-default || true
kubectl delete secret azure-service-principal -n crossplane-system || true
kubectl delete secret cnoe-kubeconfig -n crossplane-system || true
kind delete cluster --name seed
rm -f private/seed-kubeconfig private/seed-infrastructure-claim.yaml
```
Manually expire any GitHub Apps/tokens and rotate the Azure service principal secret if it will no longer be used.

## Contributing

This reference implementation is designed to be:

- **Forkable**: Create your own version for your organisation
- **Customizable**: Modify configurations without changing core packages
- **Extensible**: Add new components following the established patterns

## Troubleshooting

See [TROUBLESHOOTING.md](docs/TROUBLESHOOTING.md) for common issues and detailed troubleshooting steps.

## Manual Seed Bootstrap

The Taskfile-based seed flow has been retired. Use the minimal helper script or the manual KinD
instructions in [`docs/SEED_MANUAL.md`](docs/SEED_MANUAL.md).

```bash
./bootstrap.sh                         # expects private/kubeconfig to exist
# or REMOTE_KUBECONFIG=/path/to/aks kubeconfig ./bootstrap.sh
```

Prepare the claim manifest (located under `seed/`):

1. `seed-infrastructure-claim.yaml` – copy from `seed/seed-infrastructure-claim.yaml.example` into `private/seed-infrastructure-claim.yaml`, then replace
   every placeholder with the values from your environment (Azure identifiers, **clientObjectId**, repo metadata, GitHub App
   credentials, ApplicationSet chart location, etc.). Publish your ApplicationSet chart (e.g. by
   committing the packaged `.tgz` and `index.yaml` under `charts/` as done on branch `v2-seeding-codex`)
   and update `appsetChartRepository/appsetChartName/appsetChartVersion`
   accordingly. **Do not commit the populated file; it contains credentials and private keys.**

Create the kubeconfig secret referenced by your claim (defaults to `cnoe-kubeconfig`) using the credentials you already fetched for the remote cluster:

```bash
kubectl create secret generic cnoe-kubeconfig \
  -n crossplane-system \
  --from-file=kubeconfig=private/kubeconfig
```

Then apply everything with a single command (the composition renders the Azure service-principal secret,
Key Vault, and wildcard record, and reuses the kubeconfig secret you created above):

```bash
kubectl apply -f seed/
kubectl wait deployment/crossplane -n crossplane-system --for=condition=Available --timeout=10m
kubectl wait deployment/crossplane-rbac-manager -n crossplane-system --for=condition=Available --timeout=10m
```

When finished, delete the `azure-service-principal` secret from `crossplane-system`, remove
temporary files under `private/`, destroy the KinD cluster (`kind delete cluster --name seed`),
and remove `private/seed-infrastructure-claim.yaml` (which contains the client secret). Remove the
`cnoe-kubeconfig` secret after the run and recreate it from fresh credentials whenever you rotate
remote cluster access.

## Potential Enhancements

The installation of this Azure reference implemenation will give you a starting point for the platform, however as previously stated applications deployed in this repository are not meant or configured for production. To push it towards production ready, you can make further enhancements that could include:

1. Modifying the basic and Argo workflow templates for your specific Azure use cases
2. Intergrating additional Azure services with Crossplane
3. Configuring auto-scaling for AKS and Azure resources
4. Adding OPA Gatekeeper for governance
5. Intergrating a monitoring stack. For example:
   1. Deploy Prometheus and Grafana
   2. Configure service monitors for Azure resources
   3. View metrics and Azure resource status in Backstage
6. Implementing GitOps-based environment promotion:
   1. **Development**: Deploy to dev environment via Git push
   2. **Testing**: Promote to test environment via ArgoCD
   3. **Production**: Use ArgoCD sync waves for controlled rollout
