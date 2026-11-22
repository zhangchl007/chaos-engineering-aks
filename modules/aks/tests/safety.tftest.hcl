mock_provider "azurerm" {
  mock_resource "azurerm_kubernetes_cluster" {
    defaults = {
      id = "/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/fixture/providers/Microsoft.ContainerService/managedClusters/fixture"
    }
  }
  mock_resource "azurerm_user_assigned_identity" {
    defaults = {
      id           = "/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/fixture/providers/Microsoft.ManagedIdentity/userAssignedIdentities/aks"
      principal_id = "00000000-0000-0000-0000-000000000003"
    }
  }
}
mock_provider "random" {}
variables {
  location                    = "eastus"
  kube_version_prefix         = "1.35"
  kubernetes_version          = "1.35.1"
  node_zones                  = ["1", "2", "3"]
  kube_resource_group_name    = "fixture"
  nodepool_nodes_count        = 3
  nodepool_vm_size            = "Standard_D2s_v3"
  network_dns_service_ip      = "10.100.0.10"
  network_service_cidr        = "10.100.0.0/16"
  username                    = "fixtureadmin"
  ssh_public_key              = ""
  cluster_name                = "fixture"
  env_prefix                  = "test"
  use_existing_acr            = true
  existing_acr_name           = "fixture"
  existing_acr_resource_group = "fixture"
  subnet_ids = {
    node-subnet            = "/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/fixture/providers/Microsoft.Network/virtualNetworks/fixture/subnets/node"
    pod-subnet             = "/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/fixture/providers/Microsoft.Network/virtualNetworks/fixture/subnets/pod"
    privateendpoint-subnet = "/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/fixture/providers/Microsoft.Network/virtualNetworks/fixture/subnets/endpoints"
  }
  subnet_names = { node-subnet = "node", pod-subnet = "pod" }
}
run "private_identity_prerequisites" {
  command = plan
  plan_options {
    target = [azurerm_kubernetes_cluster.k8s]
  }
  assert {
    condition = (
      azurerm_kubernetes_cluster.k8s.private_cluster_enabled &&
      azurerm_kubernetes_cluster.k8s.local_account_disabled &&
      azurerm_kubernetes_cluster.k8s.oidc_issuer_enabled &&
      azurerm_kubernetes_cluster.k8s.workload_identity_enabled &&
      azurerm_kubernetes_cluster.k8s.azure_active_directory_role_based_access_control[0].azure_rbac_enabled
    )
    error_message = "Private API and Entra/Workload Identity prerequisites must remain enabled."
  }
  assert {
    condition     = length(azurerm_role_assignment.aks_network) == 2
    error_message = "Networking access must stay on node/pod subnets."
  }
}

run "new_registry_stays_private" {
  command = plan
  variables {
    use_existing_acr = false
    new_acr_name     = "fixture123"
  }
  plan_options {
    target = [azurerm_container_registry.default]
  }
  assert {
    condition = (
      !azurerm_container_registry.default[0].admin_enabled &&
      !azurerm_container_registry.default[0].public_network_access_enabled &&
      azurerm_container_registry.default[0].sku == "Premium"
    )
    error_message = "New registry ownership must not enable key credentials or public access."
  }
}
