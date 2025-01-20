locals {
  repo_url        = trimsuffix(var.repo_url, "/")
  subscription_id = var.subscription_id
  resource_group  = var.resource_group
  region          = var.region
  tags            = var.tags
  cluster_name    = var.cluster_name
  dns_zone_id     = provider::azurerm::parse_resource_id(var.dns_zone_id)
  dns_count       = var.enable_dns_management ? 1 : 0
  secret_count    = var.enable_external_secret ? 1 : 0

  domain_name           = var.enable_dns_management ? "${provider::azurerm::parse_resource_id(trimsuffix(data.azurerm_dns_zone.selected[0].id, "."))["resource_name"]}" : "${var.domain_name}"
  kc_domain_name        = "keycloak.${local.domain_name}"
  kc_cnoe_url           = "https://${local.kc_domain_name}/realms/cnoe"
  argo_domain_name      = "argo.${local.domain_name}"
  argo_redirect_url     = "https://${local.argo_domain_name}/oauth2/callback"
  argocd_domain_name    = "argocd.${local.domain_name}"
  backstage_domain_name = "backstage.${local.domain_name}"
}


provider "azurerm" {
  subscription_id = local.subscription_id
  features {}
}

provider "kubernetes" {
  config_path = "~/.kube/config"
}

provider "helm" {
  kubernetes {
    config_path = "~/.kube/config"
  }
}
