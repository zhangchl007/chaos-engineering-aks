variable "subscription_id" {
  description = "Explicit deployment subscription ID; verify against the approved environment mapping."
  type        = string
  validation {
    condition     = can(regex("^[0-9a-fA-F-]{36}$", var.subscription_id))
    error_message = "Provide an explicit subscription UUID."
  }
}

variable "tenant_id" {
  description = "Explicit Microsoft Entra tenant ID for Azure and kubelogin."
  type        = string
  validation {
    condition     = can(regex("^[0-9a-fA-F-]{36}$", var.tenant_id))
    error_message = "Provide an explicit tenant UUID."
  }
}

variable "cluster_name" {
  description = "Existing AKS cluster name (not a kubeconfig path)."
  type        = string
}

variable "cluster_resource_group_name" {
  description = "Resource group containing the existing AKS cluster."
  type        = string
}

variable "kubelogin_login_mode" {
  description = "Entra exec authentication: azurecli for operators, workloadidentity for federated CI."
  type        = string
  default     = "azurecli"
  validation {
    condition     = contains(["azurecli", "workloadidentity"], var.kubelogin_login_mode)
    error_message = "Use azurecli or workloadidentity; admin credentials are prohibited."
  }
}

variable "ingress_mode" {
  description = "Optional ingress controller selection; does not authorize traffic or experiments."
  type        = string
  default     = "none"
  validation {
    condition     = contains(["none", "nginx", "agfc"], var.ingress_mode)
    error_message = "ingress_mode must be none, nginx or agfc."
  }
}

variable "enable_argocd" {
  description = "Install Argo CD only when explicitly enabled."
  type        = bool
  default     = false
}

variable "env_prefix" {
  description = "Stable cluster integration release name prefix."
  type        = string
  default     = "dev"
}

variable "nginx_tls_secret_name" {
  description = "Precreated namespace/name TLS secret; required when ingress_mode=nginx."
  type        = string
  default     = ""
}

variable "allow_unsupported_nginx" {
  description = "Explicit nonproduction security exception for retired ingress-nginx."
  type        = bool
  default     = false
}

variable "allow_legacy_argocd_chart" {
  description = "Explicit nonproduction security exception for the retained legacy Argo CD chart."
  type        = bool
  default     = false
}

variable "agfc" {
  description = "Required existing platform AGFC integration contracts when ingress_mode=agfc; resources remain platform-owned."
  type = object({
    resource_group_name       = string
    resource_group_id         = string
    association_id            = string
    association_subnet_id     = string
    identity_name             = optional(string, "azure-alb-identity")
    workload_identity_enabled = optional(bool, false)
  })
  default = null
  validation {
    condition     = var.ingress_mode != "agfc" || var.agfc != null
    error_message = "AGFC mode requires existing resource group, association and delegated subnet inputs."
  }
}
