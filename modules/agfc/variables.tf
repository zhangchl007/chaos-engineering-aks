variable "resource_group_name" {
  description = "Resource Group name"
  type        = string
}

variable "location" {
  description = "Location in which to deploy AGFC"
  type        = string
}

variable "env_prefix" {
  description = "Environment prefix for naming"
  type        = string
}

variable "vnet_id" {
  description = "Virtual Network ID"
  type        = string
}

variable "subnet_id" {
  description = "Subnet ID for AGFC deployment"
  type        = string
}

variable "agfc_name" {
  description = "Application Gateway for Containers name"
  type        = string
  default     = "agfc"
}

variable "frontend_name" {
  description = "Frontend name for AGFC"
  type        = string
  default     = "agfc-frontend"
}

variable "frontend_ip" {
  description = "Deprecated private frontend input. Must remain null: AzureRM 4.55.0 cannot configure private AGFC frontends."
  type        = string
  default     = null
  validation {
    condition     = var.frontend_ip == null
    error_message = "Private AGFC frontends are not implemented by this provider/module; do not substitute DNS for private connectivity."
  }
}

variable "allow_public_frontend" {
  description = "Explicit consent to create the public frontend supported by AzureRM 4.55.0."
  type        = bool
  default     = false
}

variable "tags" {
  description = "Tags to apply to AGFC resources"
  type        = map(string)
  default     = {}
  validation {
    condition     = length(var.tags) == length(distinct([for key in keys(var.tags) : lower(key)]))
    error_message = "Azure tag names are case-insensitive; tags must not contain keys that differ only by case."
  }
}