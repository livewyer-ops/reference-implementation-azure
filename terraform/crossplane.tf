module "crossplane_azure_provider_role" {
  source = "git::https://github.com/livewyer-ops/terraform-azure-workload-identity.git"

  resource_group_name = data.azurerm_resource_group.current.name
  location            = data.azurerm_resource_group.current.location

  oidc_issuer_url             = data.azurerm_kubernetes_cluster.target.oidc_issuer_url
  create_kubernetes_namespace = false
  create_service_account      = false
  namespace                   = "crossplane-system"
  service_account_name        = "provider-azure"
  role_assignments = [{
    role_definition_name = "Owner"
    scope                = data.azurerm_resource_group.current.id
  }]
}

resource "kubectl_manifest" "application_argocd_crossplane" {
  yaml_body = templatefile("${path.module}/templates/argocd-apps/crossplane.yaml", {
    GITHUB_URL = local.repo_url
    }
  )

  provisioner "local-exec" {
    command = "kubectl wait --for=jsonpath=.status.health.status=Healthy -n argocd application/crossplane --timeout=600s &&  kubectl wait --for=jsonpath=.status.sync.status=Synced --timeout=600s -n argocd application/crossplane"

    interpreter = ["/bin/bash", "-c"]
  }

  provisioner "local-exec" {
    when = destroy

    command     = "./uninstall.sh"
    working_dir = "${path.module}/scripts/crossplane"
    interpreter = ["/bin/bash", "-c"]
  }
}

resource "kubectl_manifest" "crossplane_provider_controller_config" {
  depends_on = [
    kubectl_manifest.application_argocd_crossplane,
  ]
  yaml_body = templatefile("${path.module}/templates/manifests/crossplane-azure-controller-config.yaml", {
    AZURE_CLIENT_ID = module.crossplane_azure_provider_role.client_id
    AZURE_TENANT_ID = module.crossplane_azure_provider_role.tenant_id
    }
  )
}

resource "kubectl_manifest" "application_argocd_crossplane_provider" {
  depends_on = [
    kubectl_manifest.application_argocd_crossplane,
  ]
  yaml_body = templatefile("${path.module}/templates/argocd-apps/crossplane-provider.yaml", {
    GITHUB_URL = local.repo_url
    }
  )
}
