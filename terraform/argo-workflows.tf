#---------------------------------------------------------------
# Argo Workflows
#---------------------------------------------------------------

resource "kubernetes_manifest" "namespace_argo_workflows" {
  manifest = {
    "apiVersion" = "v1"
    "kind"       = "Namespace"
    "metadata" = {
      "name" = "argo"
    }
  }
}

resource "terraform_data" "argo_workflows_keycloak_setup" {
  depends_on = [
    kubectl_manifest.application_argocd_keycloak,
    kubernetes_manifest.namespace_argo_workflows
  ]

  provisioner "local-exec" {
    command = "./install.sh"

    working_dir = "${path.module}/scripts/argo-workflows"
    environment = {
      "ARGO_WORKFLOWS_REDIRECT_URL" = "${local.argo_redirect_url}"
    }
    interpreter = ["/bin/bash", "-c"]
  }

  provisioner "local-exec" {
    when = destroy

    command     = "./uninstall.sh"
    working_dir = "${path.module}/scripts/argo-workflows"
    interpreter = ["/bin/bash", "-c"]
  }
}

resource "kubectl_manifest" "application_argocd_argo_workflows" {
  depends_on = [
    terraform_data.argo_workflows_keycloak_setup
  ]

  yaml_body = templatefile("${path.module}/templates/argocd-apps/argo-workflows.yaml", {
    GITHUB_URL        = local.repo_url
    KEYCLOAK_CNOE_URL = local.kc_cnoe_url
    ARGO_REDIRECT_URL = local.argo_redirect_url
    }
  )
}

resource "kubectl_manifest" "application_argocd_argo_workflows_templates" {
  depends_on = [
    terraform_data.argo_workflows_keycloak_setup
  ]

  yaml_body = templatefile("${path.module}/templates/argocd-apps/argo-workflows-templates.yaml", {
    GITHUB_URL = local.repo_url
    }
  )
}

resource "kubectl_manifest" "application_argocd_argo_workflows_sso_config" {
  depends_on = [
    terraform_data.argo_workflows_keycloak_setup
  ]

  yaml_body = templatefile("${path.module}/templates/argocd-apps/argo-workflows-sso-config.yaml", {
    GITHUB_URL = local.repo_url
    }
  )
}

resource "kubectl_manifest" "ingress_argo_workflows" {
  depends_on = [
    kubectl_manifest.application_argocd_argo_workflows,
  ]

  yaml_body = templatefile("${path.module}/templates/manifests/ingress-argo-workflows.yaml", {
    ARGO_WORKFLOWS_DOMAIN_NAME = local.argo_domain_name
    }
  )
}
