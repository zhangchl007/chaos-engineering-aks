locals {
  vm_ids = merge(
    { for k, vm in azurerm_linux_virtual_machine.vm : k => vm.id },
    { for k, vm in azurerm_windows_virtual_machine.vm : k => vm.id }
  )
  connection_details = {
    for k, config in var.vms : k => {
      vm_id             = local.vm_ids[k]
      vm_name           = "${var.env_prefix}-${config.vm_name}"
      private_ip        = azurerm_network_interface.vm[k].private_ip_address
      public_ip         = config.enable_public_ip ? azurerm_public_ip.vm[k].ip_address : null
      ssh_access_status = config.protect_public_ssh ? (length(config.public_ssh_source_cidrs) > 0 ? "Configured" : "Blocked") : "Unverified"
      ssh_command = lower(config.os_type) == "linux" ? format(
        "ssh%s %s@%s",
        config.ssh_private_key_path != "" ? " -i ${jsonencode(config.ssh_private_key_path)}" : "",
        config.admin_username,
        config.enable_public_ip ? azurerm_public_ip.vm[k].ip_address : azurerm_network_interface.vm[k].private_ip_address
      ) : null
    }
  }
}

output "vm_ids" {
  description = "Map of Linux and Windows VM IDs."
  value       = local.vm_ids
}

output "vm_network_security_groups" {
  description = "Map of VM NSG details."
  value = {
    for k, nsg in azurerm_network_security_group.vm : k => {
      nsg_id   = nsg.id
      nsg_name = nsg.name
    }
  }
}

output "public_ssh_network_security_groups" {
  description = "Dedicated public SSH access NSGs, separate from original rule templates."
  value       = { for name, nsg in azurerm_network_security_group.public_ssh : name => nsg.id }
}

output "jumpserver_details" {
  description = "Jumpserver connection details and explicit SSH access status; private access requires a connected operator network."
  value       = contains(keys(var.vms), "jumpserver") ? local.connection_details["jumpserver"] : null
}

output "rocketmq_details" {
  description = "RocketMQ VM connection details only, not application readiness or verified service endpoints."
  value       = contains(keys(var.vms), "rocketmq") ? local.connection_details["rocketmq"] : null
}

output "all_vm_ssh_commands" {
  description = "SSH commands use an explicitly provided private key path when available, otherwise operator-configured SSH authentication; Windows values are null."
  value       = { for k, details in local.connection_details : k => details.ssh_command }
}
