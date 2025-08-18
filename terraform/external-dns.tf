module "external_dns_role" {
  source = "git::https://github.com/livewyer-ops/terraform-azure-workload-identity.git"

  count = local.dns_count

  resource_group_name = data.azurerm_resource_group.current.name
  location            = data.azurerm_resource_group.current.location

  oidc_issuer_url             = data.azurerm_kubernetes_cluster.target.oidc_issuer_url
  create_kubernetes_namespace = true
  create_service_account      = false
  namespace                   = "external-dns"
  service_account_name        = "external-dns"
  role_assignments = [
    {
      role_definition_name = "DNS Zone Contributor"
      scope                = data.azurerm_dns_zone.selected[0].id
    },
    {
      role_definition_name = "Reader"
      scope                = data.azurerm_resource_group.dns.id
    },
  ]
}

resource "kubectl_manifest" "application_argocd_external_dns" {
  count = local.dns_count

  yaml_body = templatefile("${path.module}/templates/argocd-apps/external-dns.yaml", {
    GITHUB_URL          = local.repo_url
    DOMAIN_NAME         = data.azurerm_dns_zone.selected[0].name
    AZURE_CLIENT_ID     = module.external_dns_role[0].client_id
    AZURE_CONFIG_SECRET = "external-dns-azure"
    }
  )

  provisioner "local-exec" {
    command     = "kubectl wait --for=jsonpath=.status.health.status=Healthy --timeout=300s -n argocd application/external-dns"
    interpreter = ["/bin/bash", "-c"]
  }

  depends_on = [kubernetes_manifest.external_dns_config]
}

resource "kubernetes_manifest" "external_dns_config" {
  count = local.dns_count

  manifest = {
    "apiVersion" = "v1"
    "kind"       = "Secret"
    "type"       = "Opaque"
    "metadata" = {
      "name"      = "external-dns-azure"
      "namespace" = "external-dns"
    }
    "data" = {
      "azure.json" = base64encode(jsonencode({
        "tenantId"                     = "${data.azurerm_subscription.current.tenant_id}"
        "subscriptionId"               = "${data.azurerm_subscription.current.subscription_id}"
        "resourceGroup"                = "${local.dns_zone_id["resource_group_name"]}"
        "useWorkloadIdentityExtension" = true
      }))
    }
  }

  depends_on = [module.external_dns_role]
}
