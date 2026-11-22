output "cluster_id" {
  description = "AKS cluster resource ID."
  value       = azurerm_kubernetes_cluster.k8s.id
}

output "node_resource_group" {
  description = "AKS-owned infrastructure resource group for approved VMSS discovery."
  value       = azurerm_kubernetes_cluster.k8s.node_resource_group
}

output "oidc_issuer_url" {
  description = "Workload identity issuer."
  value       = azurerm_kubernetes_cluster.k8s.oidc_issuer_url
}

output "acr_login_server" {
  description = "Private registry login server."
  value       = local.acr_login_server
}
