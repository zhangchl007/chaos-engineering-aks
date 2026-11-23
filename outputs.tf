output "cluster_id" {
  description = "AKS resource ID; nodes remain AKS-owned."
  value       = module.aks.cluster_id
}

output "cluster_name" {
  description = "Cluster name for the separately authenticated cluster stage."
  value       = local.cluster_name
}

output "resource_group_name" {
  description = "Single platform resource group owner."
  value       = azurerm_resource_group.kube.name
}

output "node_resource_group" {
  description = "Discovered node infrastructure resource group; never import its VMSS."
  value       = module.aks.node_resource_group
}

output "vnet_id" {
  description = "Platform VNet ID."
  value       = module.kube_network.vnet_id
}

output "subnet_ids" {
  description = "Subnet IDs for independently owned integrations."
  value       = module.kube_network.subnet_ids
}

output "oidc_issuer_url" {
  description = "Issuer for workload identity federation."
  value       = module.aks.oidc_issuer_url
}

output "mysql_admin_password" {
  description = "Enabled MySQL administrator password; read explicitly with terraform output -raw mysql_admin_password after apply."
  value       = var.components.mysql ? local.mysql_admin_password : null
  sensitive   = true
}

output "postgresql_admin_password" {
  description = "Enabled PostgreSQL administrator password; read explicitly with terraform output -raw postgresql_admin_password after apply."
  value       = var.components.postgresql ? local.postgresql_admin_password : null
  sensitive   = true
}
