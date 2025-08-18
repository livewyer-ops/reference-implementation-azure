data "azurerm_kubernetes_cluster" "target" {
  name                = local.cluster_name
  resource_group_name = local.resource_group
}

data "azurerm_dns_zone" "selected" {
  count               = local.dns_count
  name                = local.dns_zone_id["resource_name"]
  resource_group_name = local.dns_zone_id["resource_group_name"]
}

data "azurerm_resource_group" "dns" {
  name = local.dns_zone_id["resource_group_name"]
}

data "azurerm_subscription" "current" {
  subscription_id = local.subscription_id
}

data "azurerm_resource_group" "current" {
  name = local.resource_group
}

data "azurerm_client_config" "current" {}
