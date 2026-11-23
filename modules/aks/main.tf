terraform {
  required_providers {
    azurerm = { source = "hashicorp/azurerm" }
    random  = { source = "hashicorp/random" }
  }
}

resource "random_pet" "rg" {
  length = 1
  prefix = var.env_prefix
}

resource "azurerm_kubernetes_cluster" "k8s" {
  name                                = var.cluster_name
  location                            = var.location
  resource_group_name                 = var.kube_resource_group_name
  kubernetes_version                  = var.kubernetes_version
  dns_prefix                          = random_pet.rg.id
  private_cluster_enabled             = true
  private_cluster_public_fqdn_enabled = false
  azure_policy_enabled                = true
  oidc_issuer_enabled                 = true
  workload_identity_enabled           = true
  local_account_disabled              = true
  role_based_access_control_enabled   = true
  run_command_enabled                 = false
  sku_tier                            = "Standard"
  tags                                = var.tags

  default_node_pool {
    name           = "systempool"
    os_sku         = "AzureLinux"
    node_count     = var.nodepool_nodes_count
    vm_size        = var.nodepool_vm_size
    zones          = var.node_zones
    vnet_subnet_id = var.subnet_ids["node-subnet"]
    pod_subnet_id  = var.subnet_ids["pod-subnet"]
  }

  azure_active_directory_role_based_access_control {
    azure_rbac_enabled     = true
    admin_group_object_ids = var.cluster_admin_group_object_ids
  }

  identity {
    type         = "UserAssigned"
    identity_ids = [azurerm_user_assigned_identity.aks.id]
  }

  network_profile {
    network_plugin    = "azure"
    load_balancer_sku = "standard"
    dns_service_ip    = var.network_dns_service_ip
    service_cidr      = var.network_service_cidr
  }

  dynamic "linux_profile" {
    for_each = var.ssh_public_key == "" ? [] : [var.ssh_public_key]
    content {
      admin_username = var.username
      ssh_key {
        key_data = file(pathexpand(linux_profile.value))
      }
    }
  }

  dynamic "oms_agent" {
    for_each = var.log_analytics_workspace_id == null ? [] : [var.log_analytics_workspace_id]
    content {
      log_analytics_workspace_id      = oms_agent.value
      msi_auth_for_monitoring_enabled = true
    }
  }

  lifecycle {
    # These service-assigned settings have no configuration inputs in this module.
    ignore_changes = [
      default_node_pool[0].upgrade_settings,
      microsoft_defender,
    ]
  }

  depends_on = [azurerm_role_assignment.aks_network]
}

resource "azurerm_kubernetes_cluster_node_pool" "spotnodepool" {
  name                  = "spotnodepool"
  kubernetes_cluster_id = azurerm_kubernetes_cluster.k8s.id
  vm_size               = var.nodepool_vm_size
  os_sku                = "AzureLinux"
  node_count            = var.nodepool_nodes_count
  zones                 = var.node_zones
  vnet_subnet_id        = var.subnet_ids["node-subnet"]
  pod_subnet_id         = var.subnet_ids["pod-subnet"]
  mode                  = "User"
  tags                  = var.tags

  lifecycle {
    ignore_changes = [upgrade_settings]
  }
}
