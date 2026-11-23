output "cluster_id" {
  description = "Existing target AKS ID, never managed by this stack."
  value       = data.azurerm_kubernetes_cluster.target.id
}

output "ingress_release_name" {
  description = "NGINX release name, or null when not selected."
  value       = var.ingress_mode == "nginx" ? module.ingress[0].release_name : null
}

output "argocd_namespace" {
  description = "Argo CD namespace, or null when disabled; no credentials exposed."
  value       = var.enable_argocd ? module.argocd[0].namespace : null
}

output "agfc_controller_identity_id" {
  description = "ALB controller UAMI ID, or null when AGFC is disabled."
  value       = var.ingress_mode == "agfc" && var.agfc != null ? module.agfc_controller["active"].identity_id : null
}
