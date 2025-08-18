
#---------------------------------------------------------------
# External Secrets for Keycloak if enabled
#---------------------------------------------------------------

module "external_secrets_role_keycloak" {
  source = "git::https://github.com/livewyer-ops/terraform-azure-workload-identity.git"

  count = local.secret_count

  resource_group_name = data.azurerm_resource_group.current.name
  location            = data.azurerm_resource_group.current.location

  oidc_issuer_url             = data.azurerm_kubernetes_cluster.target.oidc_issuer_url
  create_kubernetes_namespace = false
  create_service_account      = false
  namespace                   = "keycloak"
  service_account_name        = "external-secret-keycloak"
  role_assignments = [
    {
      role_definition_name = "Key Vault Secrets User"
      scope                = azurerm_key_vault.keycloak_config[0].id
    },
    {
      role_definition_name = "Key Vault Reader"
      scope                = azurerm_key_vault.keycloak_config[0].id
    },
  ]

  depends_on = [kubernetes_manifest.namespace_keycloak[0]]
}

# should use gitops really.
resource "kubernetes_manifest" "namespace_keycloak" {
  count = local.secret_count

  manifest = {
    "apiVersion" = "v1"
    "kind"       = "Namespace"
    "metadata" = {
      "name" = "keycloak"
    }
  }
}

resource "kubernetes_manifest" "serviceaccount_external_secret_keycloak" {
  count = local.secret_count
  depends_on = [
    kubernetes_manifest.namespace_keycloak,
    kubectl_manifest.application_argocd_external_secrets,
    module.external_secrets_role_keycloak
  ]

  manifest = {
    "apiVersion" = "v1"
    "kind"       = "ServiceAccount"
    "metadata" = {
      "annotations" = {
        "azure.workload.identity/client-id" = tostring(module.external_secrets_role_keycloak[0].client_id)
        "azure.workload.identity/tenant-id" = tostring(module.external_secrets_role_keycloak[0].tenant_id)
      }
      "name"      = "external-secret-keycloak"
      "namespace" = "keycloak"
    }
  }
}

resource "azurerm_key_vault" "keycloak_config" {
  count = local.secret_count

  name                      = "cnoe-keycloak-config"
  location                  = data.azurerm_resource_group.current.location
  resource_group_name       = data.azurerm_resource_group.current.name
  tenant_id                 = data.azurerm_client_config.current.tenant_id
  sku_name                  = "standard"
  enable_rbac_authorization = true
  access_policy {
    tenant_id          = data.azurerm_client_config.current.tenant_id
    object_id          = data.azurerm_client_config.current.object_id
    secret_permissions = ["Backup", "Delete", "Get", "List", "Purge", "Recover", "Restore", "Set"]
  }
  access_policy {
    tenant_id          = module.external_secrets_role_keycloak[0].tenant_id
    object_id          = module.external_secrets_role_keycloak[0].client_id
    secret_permissions = ["Get", "List"]
  }
}

resource "azurerm_key_vault_secret" "keycloak_config" {
  count = local.secret_count

  name         = "cnoe-keycloak-config"
  key_vault_id = azurerm_key_vault.keycloak_config[0].id
  value = jsonencode({
    KC_HOSTNAME             = local.kc_domain_name
    KEYCLOAK_ADMIN_PASSWORD = random_password.keycloak_admin_password.result
    POSTGRES_PASSWORD       = random_password.keycloak_postgres_password.result
    POSTGRES_DB             = "keycloak"
    POSTGRES_USER           = "keycloak"
    "user1-password"        = random_password.keycloak_user_password.result
  })

  depends_on = [azurerm_role_assignment.keycloak_config[0]]
}

resource "azurerm_role_assignment" "keycloak_config" {
  count = local.secret_count

  scope                = azurerm_key_vault.keycloak_config[0].id
  role_definition_name = "Key Vault Administrator"
  principal_id         = data.azurerm_client_config.current.object_id
}

resource "kubectl_manifest" "keycloak_secret_store" {
  count = local.secret_count

  depends_on = [
    kubectl_manifest.application_argocd_external_secrets,
    kubernetes_manifest.serviceaccount_external_secret_keycloak,
    module.external_secrets_role_keycloak,
    azurerm_key_vault_secret.keycloak_config,
  ]

  yaml_body = templatefile("${path.module}/templates/manifests/keycloak-secret-store.yaml", {
    VAULT_URL = azurerm_key_vault.keycloak_config[0].vault_uri
    SA_NAME   = "external-secret-keycloak"
    }
  )
}

#---------------------------------------------------------------
# Keycloak secrets if external secrets is not enabled
#---------------------------------------------------------------

resource "kubernetes_manifest" "secret_keycloak_keycloak_config" {
  count = local.secret_count == 1 ? 0 : 1

  manifest = {
    "apiVersion" = "v1"
    "kind"       = "Secret"
    "metadata" = {
      "name"      = "keycloak-config"
      "namespace" = "keycloak"
    }
    "data" = {
      "KC_HOSTNAME"             = "${base64encode(local.kc_domain_name)}"
      "KEYCLOAK_ADMIN_PASSWORD" = "${base64encode(random_password.keycloak_admin_password.result)}"
    }
  }
}

resource "kubernetes_manifest" "secret_keycloak_postgresql_config" {
  count = local.secret_count == 1 ? 0 : 1

  manifest = {
    "apiVersion" = "v1"
    "kind"       = "Secret"
    "metadata" = {
      "name"      = "postgresql-config"
      "namespace" = "keycloak"
    }
    "data" = {
      "POSTGRES_DB"       = "${base64encode("keycloak")}"
      "POSTGRES_PASSWORD" = "${base64encode(random_password.keycloak_postgres_password.result)}"
      "POSTGRES_USER"     = "${base64encode("keycloak")}"
    }
  }
}

resource "kubernetes_manifest" "secret_keycloak_keycloak_user_config" {
  count = local.secret_count == 1 ? 0 : 1

  manifest = {
    "apiVersion" = "v1"
    "kind"       = "Secret"
    "metadata" = {
      "name"      = "keycloak-user-config"
      "namespace" = "keycloak"
    }
    "data" = {
      "user1-password" = "${base64encode(random_password.keycloak_user_password.result)}"
    }
  }
}

#---------------------------------------------------------------
# Keycloak passwords
#---------------------------------------------------------------

resource "random_password" "keycloak_admin_password" {
  length           = 48
  special          = false
  override_special = "!#?"
}

resource "random_password" "keycloak_user_password" {
  length           = 48
  special          = false
  override_special = "!#?"
}

resource "random_password" "keycloak_postgres_password" {
  length           = 48
  special          = false
  override_special = "!#?"
}

#---------------------------------------------------------------
# Keycloak installation
#---------------------------------------------------------------

resource "kubectl_manifest" "application_argocd_keycloak" {
  depends_on = [kubectl_manifest.keycloak_secret_store]

  yaml_body = templatefile("${path.module}/templates/argocd-apps/keycloak.yaml", {
    GITHUB_URL = local.repo_url
    PATH       = "${local.secret_count == 1 ? "packages/keycloak/dev-external-secrets/" : "packages/keycloak/dev/"}"
    }
  )

  provisioner "local-exec" {
    command = "./install.sh '${random_password.keycloak_user_password.result}' '${random_password.keycloak_admin_password.result}'"

    working_dir = "${path.module}/scripts/keycloak"
    interpreter = ["/bin/bash", "-c"]
  }
  provisioner "local-exec" {
    when    = destroy
    command = "./uninstall.sh"

    working_dir = "${path.module}/scripts/keycloak"
    interpreter = ["/bin/bash", "-c"]
  }
}

resource "kubectl_manifest" "ingress_keycloak" {
  depends_on = [
    kubectl_manifest.application_argocd_keycloak,
  ]

  yaml_body = templatefile("${path.module}/templates/manifests/ingress-keycloak.yaml", {
    KEYCLOAK_DOMAIN_NAME = local.kc_domain_name
    }
  )
}
