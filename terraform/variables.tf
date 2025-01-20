variable "repo_url" {
  description = "Repository URL where application definitions are stored"
  default     = "https://github.com/manabuOrg/ref-impl"
  type        = string
}

variable "tags" {
  description = "Tags to apply to AKS resources"
  default = {
    env     = "dev"
    project = "cnoe"
  }
  type = map(string)
}

variable "region" {
  description = "Azure Region"
  type        = string
  default     = ""
}

variable "subscription_id" {
  description = "Azure Subscription ID"
  type        = string
  default     = ""
}

variable "resource_group" {
  description = "Azure Resource Group name"
  type        = string
  default     = ""
}

variable "cluster_name" {
  description = "AKS Cluster name"
  default     = "cnoe-ref-impl"
  type        = string
}

variable "dns_zone_id" {
  description = "If using external DNS, specify the Azure DNS zone ID. Required if enable_dns_management is set to true."
  default     = ""
  type        = string
}

variable "domain_name" {
  description = "if external DNS is not used, this value must be provided."
  default     = "svc.cluster.local"
  type        = string
}

variable "organization_url" {
  description = "github organization url"
  default     = "https://github.com/cnoe-io"
  type        = string
}

variable "enable_dns_management" {
  description = "Do you want to use external dns to manage dns records in Azure DNS?"
  default     = true
  type        = bool
}

variable "enable_external_secret" {
  description = "Do you want to use external secret to manage dns records in Azure DNS?"
  default     = true
  type        = bool
}

variable "service_account_token_expiration_seconds" {
  type        = number
  description = "(optional) Represents the expirationSeconds field for the projected service account token"
  default     = 86400
}
