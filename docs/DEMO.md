# Demo Guide - CNOE Azure Reference Implementation

This guide demonstrates the key features and capabilities of the CNOE Azure Reference Implementation through practical examples focused on Azure services and infrastructure.

## Prerequisites

- Complete installation following the [README](../README.md)
- All prerequisite Azure resources (AKS cluster, DNS zone, Key Vault) properly configured
- Access to Backstage UI at your configured domain
- Default users (`user1`, `user2`) credentials from Keycloak

## Getting Started

### 1. Access the Platform

Navigate to your Backstage instance:

- **Domain routing**: `https://backstage.YOUR_DOMAIN`
- **Path routing**: `https://YOUR_DOMAIN`

Login with the default credentials:

```bash
# Get user passwords
kubectl get secrets -n keycloak keycloak-user-config -o go-template='{{range $k,$v := .data}}{{printf "%s: " $k}}{{if not $v}}{{$v}}{{else}}{{$v | base64decode}}{{end}}{{"\n"}}{{end}}'
```

### 2. Platform Overview

Once logged in, you'll see the Backstage home page with:

- **Software Catalog**: Discover services, APIs, and resources
- **Software Templates**: Create new projects from templates
- **Argo Workflows**: View and manage workflow executions
- **ArgoCD**: Monitor deployments and sync status

## Demo Scenarios

### Scenario 1: Exploring the Software Catalog

The Software Catalog provides a centralized view of all your software components.

1. **Navigate to Catalog**: Click on "Catalog" in the sidebar

- **View Entities**: You'll see various entity types:
  - **Components**: Microservices and applications
  - **APIs**: Service interfaces
  - **Systems**: Business capabilities
  - **Domains**: Business areas

3. **Filter and Search**:
   - Use filters to narrow down by type, owner, or tags
   - Search for specific components
   - View ownership and relationships

4. **Component Details**: Click on any component to see:
   - Overview and documentation
   - API specs
   - Dependencies and relationships
   - Recent deployments
   - Metrics and monitoring links

### Scenario 2: Creating a New Application from Template

Backstage templates accelerate development by providing standardized project scaffolding.

#### Basic Application Template

1. **Access Templates**: Click "Create..." in the sidebar
2. **Select Template**: Choose "Create a Basic Deployment"
3. **Fill Parameters**:
   ```yaml
   name: my-demo-app
   description: A demo application for testing
   ```
4. **Generate**: Click "Create" to generate the repository
5. **Review**: The template creates:
   - GitHub repository with application code
   - Basic Kubernetes deployment manifest
   - ArgoCD application configuration
   - Backstage catalog entry

#### Argo Workflows Template

1. **Select Template**: Choose "Basic Argo Workflow with a Spark Job"
2. **Configure Workflow**:
   ```yaml
   name: spark-demo-pipeline
   description: Example Spark job with Argo Workflows
   ```
3. **Deploy**: The template creates a workflow definition with a Spark job that can be triggered immediately

### Scenario 3: Managing Deployments with ArgoCD

Monitor and manage application deployments through the integrated ArgoCD interface.

1. **Access ArgoCD**:
   - Via Backstage: Click "ArgoCD" in the navigation
   - Direct access: `https://argocd.YOUR_DOMAIN` (or path-based URL)

2. **View Applications**: See all deployed applications with their sync status
3. **Application Details**: Click on an application to see:
   - Resource tree showing Kubernetes objects
   - Sync status and health
   - Recent deployment history
   - Configuration drift detection

4. **Sync Operations**:
   - **Manual Sync**: Force synchronization with Git
   - **Rollback**: Revert to previous version
   - **Refresh**: Update from Git repository

### Scenario 4: Running Workflows with Argo Workflows

Execute data processing, CI/CD, and automation workflows.

1. **Access Argo Workflows**:
   - Via Backstage: Navigate to workflows section
   - Direct access: `https://argo-workflows.YOUR_DOMAIN`

2. **Submit a Workflow**:

   ```yaml
   apiVersion: argoproj.io/v1alpha1
   kind: Workflow
   metadata:
     generateName: hello-world-
   spec:
     entrypoint: whalesay
     templates:
       - name: whalesay
         container:
           image: docker/whalesay
           command: [cowsay]
           args: ["Hello CNOE!"]
   ```

3. **Monitor Execution**:
   - View workflow progress in real-time
   - Check logs for each step
   - Monitor resource usage

4. **Workflow Templates**: The available templates include:
   - **Spark Jobs**: Apache Spark data processing workflows
   - **RBAC Configuration**: Service account and role binding setup

### Scenario 5: Infrastructure as Code with Crossplane

Manage Azure cloud resources using Kubernetes-native APIs through the configured Crossplane provider.

1. **Create Azure Workload Identity**:

   ```yaml
   apiVersion: azure.livewyer.io/v1alpha1
   kind: WorkloadIdentity
   metadata:
     name: demo-workload-identity
     namespace: demo
   spec:
     forProvider:
       location: eastus
       oidcIssuerURL: "https://eastus.oic.prod-aks.azure.com/your-tenant-id/your-cluster-id/"
       resourceGroupName: your-resource-group
       roleAssignments:
         - roleDefinitionName: Contributor
           scope: "/subscriptions/your-subscription-id/resourceGroups/your-resource-group"
       serviceAccountName: demo-service-account
   ```

2. **Deploy Additional Workload Identity with specific permissions**:

   ```yaml
   apiVersion: azure.livewyer.io/v1alpha1
   kind: WorkloadIdentity
   metadata:
     name: demo-storage-identity
     namespace: demo
   spec:
     forProvider:
       location: eastus
       oidcIssuerURL: "https://eastus.oic.prod-aks.azure.com/your-tenant-id/your-cluster-id/"
       resourceGroupName: your-resource-group
       roleAssignments:
         - roleDefinitionName: Storage Blob Data Contributor
           scope: "/subscriptions/your-subscription-id/resourceGroups/your-resource-group"
       serviceAccountName: storage-service-account
   ```

3. **Monitor Resources**: View created resources in ArgoCD and Azure portal via the Crossplane workload identity

### Scenario 6: Secret Management

Demonstrate secure secret handling with External Secrets and Azure Key Vault.

1. **Store Secret in Key Vault**:

   ```bash
   az keyvault secret set --name "demo-api-key" --value "super-secret-key" --vault-name YOUR_KEYVAULT
   ```

2. **Create External Secret**:

   ```yaml
   apiVersion: external-secrets.io/v1beta1
   kind: ExternalSecret
   metadata:
     name: demo-secret
     namespace: demo
   spec:
     secretStoreRef:
       name: azure-keyvault-store
       kind: SecretStore
     target:
       name: demo-secret
       creationPolicy: Owner
     data:
       - secretKey: api-key
         remoteRef:
           key: demo-api-key
   ```

3. **Use in Application**: Reference the secret in your deployment

### Scenario 7: DNS and TLS Management

Show automatic DNS and certificate management.

1. **Deploy Application with Ingress**:

   ```yaml
   apiVersion: networking.k8s.io/v1
   kind: Ingress
   metadata:
     name: demo-app
     annotations:
       cert-manager.io/cluster-issuer: letsencrypt-prod
   spec:
     tls:
       - hosts:
           - demo-app.YOUR_DOMAIN
         secretName: demo-app-tls
     rules:
       - host: demo-app.YOUR_DOMAIN
         http:
           paths:
             - path: /
               pathType: Prefix
               backend:
                 service:
                   name: demo-app
                   port:
                     number: 80
   ```

2. **Observe Automation**:
   - External-DNS creates DNS record
   - Cert-manager issues TLS certificate
   - Application becomes accessible with HTTPS

## Configuration Management Demo

### Understanding config.yaml

All platform configuration is centralized in `config.yaml`. This includes:

```yaml
# Example configuration structure
repo:
  url: https://github.com/your-org/cnoe-reference-implementation-azure
  revision: main

cluster_name: your-aks-cluster
subscription: your-azure-subscription-id
location: eastus
resource_group: your-resource-group
domain: your-domain.com
keyvault: your-key-vault

github:
  appId: "1234567"
  installationId: "8901234"
  orgURL: https://github.com/your-org
  clientId: your-client-id
  clientSecret: your-client-secret
  # All GitHub integration details are here, not in private files

crossplane_workload_identity:
  clientId: your-crossplane-client-id
  tenantId: your-tenant-id
```

### Updating Configuration

```bash
# Make changes to config.yaml
vim config.yaml

# Update the platform configuration
task update

# Sync changes to all components
task sync
```

### Task Usage Examples

```bash
# View configuration differences before applying
task diff

# Deploy updates (equivalent to helmfile sync)
task sync

# Update only the configuration secrets in Key Vault
task update:secret

# Initialize and validate configuration
task init

# Full reinstallation
task uninstall
task install
```

## Advanced Use Cases

### Multi-Environment Promotion

Demonstrate GitOps-based environment promotion:

1. **Development**: Deploy to dev environment via Git push
2. **Testing**: Promote to test environment via ArgoCD
3. **Production**: Use ArgoCD sync waves for controlled rollout

### Azure Integration Examples

Show Azure-specific integrations:

1. **Azure Key Vault**: Store and retrieve secrets via External Secrets
2. **Azure DNS**: Automatic DNS record management via External-DNS
3. **Azure Storage**: Create and manage storage accounts via Crossplane
4. **Azure Workload Identity**: Secure, keyless authentication to Azure services

### Monitoring and Observability

Integrate monitoring stack:

1. Deploy Prometheus and Grafana
2. Configure service monitors for Azure resources
3. View metrics and Azure resource status in Backstage

## Troubleshooting Common Demo Issues

### Application Not Syncing

1. Check ArgoCD application health
2. Verify Git repository access
3. Review sync policy configuration

### Certificate Not Issued

1. Check cert-manager logs
2. Verify DNS propagation
3. Validate ACME challenge completion

### Workflow Failing

1. Check workflow logs in Argo Workflows UI
2. Verify service account permissions
3. Validate resource requests and limits

### Configuration Issues

1. **GitHub Integration Problems**:

   ```bash
   # Verify GitHub app configuration in config.yaml
   yq '.github' config.yaml

   # Check if configuration was properly uploaded to Key Vault
   az keyvault secret show --name config --vault-name $(yq '.keyvault' config.yaml)
   ```

2. **DNS Resolution Issues**:

   ```bash
   # Test DNS resolution
   nslookup backstage.$(yq '.domain' config.yaml)

   # Check external-dns logs
   kubectl logs -n external-dns deployment/external-dns

   # Verify Azure DNS zone
   az network dns zone show --name $(yq '.domain' config.yaml) --resource-group $(yq '.resource_group' config.yaml)
   ```

## Best Practices Demonstrated

### 1. GitOps Workflow

- All changes through Git
- Declarative configuration
- Automated reconciliation

### 2. Security

- Workload Identity for Azure authentication
- Secret management with External Secrets
- TLS everywhere with cert-manager
- Configuration stored securely in Azure Key Vault

### 3. Developer Experience

- Self-service via Backstage templates
- Integrated tooling in single interface
- Documentation as code

### 4. Operational Excellence

- Infrastructure as Code
- Automated DNS and certificate management
- Comprehensive monitoring
- Centralized configuration management

## Task Usage Guidelines

### Production vs Demo Tasks

**Production Tasks** (safe for production use):

```bash
task install    # Full installation
task sync       # Update components (helmfile sync equivalent)
task update     # Update configuration secrets
task diff       # Show pending changes
task uninstall  # Clean removal
```

**Demo/Helper Tasks** (for demonstration and testing only):

```bash
task test:aks:create     # Creates test AKS cluster - NOT for production
task test:aks:destroy    # Removes test AKS cluster
task azure:creds:create  # Creates demo Azure credentials - NOT for production
task azure:creds:delete  # Removes demo Azure credentials
```

> **Important**: Tasks prefixed with `test:` or `azure:creds:` are helper functions for demonstration purposes only. Production Azure resources should be managed through your organization's standard infrastructure management practices (Terraform, Bicep, ARM templates, etc.).

## Next Steps

After completing these demos, consider:

1. **Customizing Templates**: Modify the basic and Argo workflow templates for your specific Azure use cases
2. **Adding Azure Integrations**: Connect additional Azure services via Crossplane
3. **Implementing Policies**: Add OPA Gatekeeper for governance
4. **Scaling**: Configure auto-scaling for AKS and Azure resources
5. **Production Deployment**: Implement proper infrastructure management for Azure resources using enterprise tools

## Additional Resources

- [Backstage Documentation](https://backstage.io/docs/)
- [ArgoCD User Guide](https://argo-cd.readthedocs.io/en/stable/)
- [Argo Workflows Examples](https://github.com/argoproj/argo-workflows/tree/master/examples)
- [Crossplane Documentation](https://docs.crossplane.io/)
- [CNOE Project](https://cnoe.io/)
- [Azure Workload Identity](https://azure.github.io/azure-workload-identity/)

## Feedback and Contributions

Found an issue or have suggestions?

- Open an issue in the repository
- Submit a pull request with improvements
- Join the CNOE community discussions
