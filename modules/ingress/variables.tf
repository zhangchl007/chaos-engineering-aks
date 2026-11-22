variable "resource_group_name" {
  description = "Resource Group name"
  type        = string
}

variable "location" {
  description = "Location in which to deploy the network"
  type        = string
}

variable "env_prefix" {
  type        = string
  description = "DNS Prefix"
  default     = "tf"
}

variable "ingress_repository" {
  description = "The repository of the ingress controller"
  type        = string
  default     = "https://kubernetes.github.io/ingress-nginx"

}

variable "ingress_chart" {
  description = "The chart of the ingress controller"
  type        = string
  default     = "ingress-nginx"

}

variable "ingress_version" {
  description = "The version of the ingress controller"
  type        = string
  default     = "4.0.18"
  validation {
    condition     = can(regex("^[0-9]+\\.[0-9]+\\.[0-9]+$", var.ingress_version))
    error_message = "Use an explicit chart version."
  }
}

variable "tls_secret_name" {
  description = "Existing TLS secret as namespace/name, provisioned separately without putting private keys in Terraform state."
  type        = string
  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9-]*/[a-z0-9][a-z0-9.-]*$", var.tls_secret_name))
    error_message = "Provide a nonempty namespace/name TLS secret reference."
  }
}

variable "allow_unsupported_nginx" {
  description = "Explicit nonproduction exception for the retired ingress-nginx controller and legacy chart."
  type        = bool
  default     = false
  validation {
    condition     = var.allow_unsupported_nginx
    error_message = "Ingress-nginx is retired in 2026. Deployment is blocked without explicit nonproduction security exception."
  }
}
variable "ingress_namespace" {
  description = "The namespace for the ingress controller"
  type        = string
  default     = "ingress-nginx"
}