variable "resource_group_name" {
  description = "Existing resource group in which this module owns the controller identity."
  type        = string
}

variable "location" {
  description = "Azure region for the controller identity."
  type        = string
}

variable "identity_name" {
  description = "Controller UAMI name."
  type        = string
  default     = "azure-alb-identity"
}

variable "oidc_issuer_url" {
  description = "OIDC issuer URL of the target AKS cluster; workload identity must already be enabled."
  type        = string
  validation {
    condition     = can(regex("^https://[^ ]+/$", var.oidc_issuer_url))
    error_message = "Supply the AKS HTTPS OIDC issuer URL including its trailing slash."
  }
}

variable "node_resource_group_id" {
  description = "Existing AKS node resource group ID, discovered from AKS (Reader only)."
  type        = string
  validation {
    condition     = can(regex("(?i)^/subscriptions/[^/]+/resourceGroups/[^/]+$", var.node_resource_group_id))
    error_message = "Reader scope must be an explicit resource group ID, not a subscription."
  }
}

variable "agfc_resource_group_id" {
  description = "Existing AGFC resource group ID; documented Configuration Manager scope."
  type        = string
  validation {
    condition     = can(regex("(?i)^/subscriptions/[^/]+/resourceGroups/[^/]+$", var.agfc_resource_group_id))
    error_message = "Configuration Manager scope must be an explicit resource group ID."
  }
}

variable "association_subnet_id" {
  description = "Existing delegated association subnet ID; Network Contributor is limited to this subnet."
  type        = string
  validation {
    condition     = can(regex("(?i)^/subscriptions/[^/]+/resourceGroups/[^/]+/providers/Microsoft.Network/virtualNetworks/[^/]+/subnets/[^/]+$", var.association_subnet_id))
    error_message = "Provide the exact delegated association subnet ID."
  }
}

variable "association_id" {
  description = "Platform-owned AGFC association ID; used only as an integration contract, never managed or imported here."
  type        = string
  validation {
    condition = can(regex(
      "(?i)^/subscriptions/[^/]+/resourceGroups/[^/]+/providers/Microsoft.ServiceNetworking/trafficControllers/[^/]+/associations/[^/]+$", var.association_id
    )) && startswith(lower(var.association_id), "${lower(var.agfc_resource_group_id)}/")
    error_message = "Association must belong to the supplied AGFC resource group."
  }
}

variable "controller_namespace" {
  description = "Namespace owned by the official chart; federation uses its alb-controller-sa account."
  type        = string
  default     = "azure-alb-system"
  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9-]*$", var.controller_namespace))
    error_message = "Use a valid dedicated namespace."
  }
}

variable "tags" {
  description = "Tags for the controller UAMI."
  type        = map(string)
  default     = {}
}

variable "workload_identity_enabled" {
  description = "Verified AKS Workload Identity setting; the controller does not mutate the cluster."
  type        = bool
  validation {
    condition     = var.workload_identity_enabled
    error_message = "ALB controller requires Workload Identity enabled in the platform stage."
  }
}
