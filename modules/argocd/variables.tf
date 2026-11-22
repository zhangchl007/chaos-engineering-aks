
variable "argocd_name" {
  description = "The name of the ArgoCD release."
  type        = string
  default     = "argocd"
}
variable "argocd_namespace" {
  description = "The namespace where ArgoCD will be installed."
  type        = string
  default     = "argocd"
}
variable "argocd_repository" {
  description = "The Helm repository for ArgoCD."
  type        = string
  default     = "https://argoproj.github.io/argo-helm"
}
variable "argocd_chart" {
  description = "The Helm chart for ArgoCD."
  type        = string
  default     = "argo-cd"
}
variable "argocd_version" {
  description = "The version of the ArgoCD Helm chart."
  type        = string
  default     = "5.24.1"
}
variable "kubeconfig_path" {
  description = "Deprecated compatibility input; ignored. Providers must be passed from the cluster stack."
  type        = string
  default     = null
}

variable "allow_legacy_chart" {
  description = "Explicit nonproduction security exception for the retained legacy Argo CD chart, pending a separately validated upgrade."
  type        = bool
  default     = false
  validation {
    condition     = var.allow_legacy_chart
    error_message = "The retained Argo CD chart is legacy. Review security and compatibility before granting this explicit exception."
  }
}

variable "tls_secret_name" {
  description = "Existing server TLS secret in the Argo CD namespace; chart expects argocd-server-tls."
  type        = string
  default     = "argocd-server-tls"
  validation {
    condition     = var.tls_secret_name == "argocd-server-tls"
    error_message = "Provision argocd-server-tls independently; private keys must not be passed to Terraform."
  }
}