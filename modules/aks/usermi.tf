resource "azurerm_user_assigned_identity" "aks" {
  location            = var.location
  name                = "${var.env_prefix}-aks"
  resource_group_name = var.kube_resource_group_name
  tags                = var.tags
}

resource "azurerm_role_assignment" "aks_network" {
  for_each             = { node = var.subnet_ids["node-subnet"], pod = var.subnet_ids["pod-subnet"] }
  scope                = each.value
  role_definition_name = "Network Contributor"
  principal_id         = azurerm_user_assigned_identity.aks.principal_id
}

moved {
  from = azurerm_role_assignment.aks_network
  to   = azurerm_role_assignment.aks_network["node"]
}

resource "azurerm_role_assignment" "aks_acr_pull" {
  principal_id                     = azurerm_kubernetes_cluster.k8s.kubelet_identity[0].object_id
  role_definition_name             = "AcrPull"
  scope                            = local.acr_id
  skip_service_principal_aad_check = true
}
