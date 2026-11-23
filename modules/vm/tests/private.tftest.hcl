mock_provider "azurerm" {
  mock_resource "azurerm_public_ip" {
    defaults = {
      id         = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/test-vm-rg/providers/Microsoft.Network/publicIPAddresses/test"
      ip_address = "203.0.113.10"
    }
  }
  mock_resource "azurerm_network_interface" {
    defaults = {
      id                 = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/test-vm-rg/providers/Microsoft.Network/networkInterfaces/test"
      private_ip_address = "10.0.1.4"
    }
  }
  mock_resource "azurerm_network_security_group" {
    defaults = {
      id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/test-vm-rg/providers/Microsoft.Network/networkSecurityGroups/test"
    }
  }
  mock_resource "azurerm_linux_virtual_machine" {
    defaults = {
      id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/test-vm-rg/providers/Microsoft.Compute/virtualMachines/test"
    }
  }
}

mock_provider "random" {
  mock_resource "random_password" {
    defaults = {
      result = "MockOnly1!NotASecret"
    }
  }
}

variables {
  resource_group_name = "test-vm-rg"
  location            = "westeurope"
  env_prefix          = "test"
  vnet_id             = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/test-vm-rg/providers/Microsoft.Network/virtualNetworks/test"
  subnet_ids = {
    vm = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/test-vm-rg/providers/Microsoft.Network/virtualNetworks/test/subnets/vm"
  }
}

run "private_linux_and_windows_outputs" {
  command = apply
  variables {
    tags = { environment = "dev" }
    vms = {
      jumpserver = {
        vm_name              = "jumpserver"
        vm_size              = "Standard_D2s_v5"
        subnet_name          = "vm"
        admin_username       = "testuser"
        ssh_public_key_path  = "tests/fixtures/test.pub"
        ssh_private_key_path = "/operator/keys/test"
        image_version        = "20.04.202111020"
      }
      windows = {
        vm_name             = "windows"
        vm_size             = "Standard_D2s_v5"
        subnet_name         = "vm"
        admin_username      = "testuser"
        ssh_public_key_path = ""
        os_type             = "windows"
        image_publisher     = "MicrosoftWindowsServer"
        image_offer         = "WindowsServer"
        image_sku           = "2022-datacenter-azure-edition"
        image_version       = "20348.2402.240406"
        tags                = { Environment = "windows-test" }
      }
    }
  }
  assert {
    condition     = length(azurerm_public_ip.vm) == 0
    error_message = "VMs must not create public IPs by default."
  }
  assert {
    condition     = length(azurerm_network_interface_security_group_association.vm) == 2
    error_message = "Clean deployments must retain the existing default NIC/NSG association behavior."
  }
  assert {
    condition     = azurerm_linux_virtual_machine.vm["jumpserver"].tags["environment"] == "dev" && !contains(keys(azurerm_linux_virtual_machine.vm["jumpserver"].tags), "Environment") && alltrue([for tags in [azurerm_windows_virtual_machine.vm["windows"].tags, azurerm_network_interface.vm["windows"].tags, azurerm_network_security_group.vm["windows"].tags] : tags["Environment"] == "windows-test" && !contains(keys(tags), "environment")])
    error_message = "Global and per-VM tags must override inherited case variants without duplicate Azure keys."
  }
  assert {
    condition     = output.jumpserver_details != null && output.jumpserver_details.public_ip == null
    error_message = "A private jumpserver must retain its connection output, not become null."
  }
  assert {
    condition     = strcontains(output.jumpserver_details.ssh_command, "/operator/keys/test") && strcontains(output.jumpserver_details.ssh_command, "testuser@10.0.1.4")
    error_message = "SSH instructions must use the provided key, user and private IP."
  }
  assert {
    condition     = contains(keys(output.vm_ids), "windows") && output.all_vm_ssh_commands["windows"] == null
    error_message = "Windows IDs must be included without inventing SSH commands."
  }
}

run "invalid_image_version_rejected" {
  command = plan
  variables {
    vms = {
      bad = {
        vm_name              = "bad"
        vm_size              = "Standard_D2s_v5"
        subnet_name          = "vm"
        admin_username       = "testuser"
        ssh_public_key_path  = "tests/fixtures/test.pub"
        ssh_private_key_path = "/operator/keys/test"
        image_version        = "unverified-image"
      }
    }
  }
  expect_failures = [var.vms]
}

run "rocketmq_bootstrap_is_cloud_init_on_a_private_vm" {
  command = apply
  variables {
    vms = {
      rocketmq = {
        vm_name             = "rocketmq"
        vm_size             = "Standard_D2s_v3"
        subnet_name         = "vm"
        admin_username      = "testuser"
        ssh_public_key_path = "tests/fixtures/test.pub"
        image_offer         = "0001-com-ubuntu-server-jammy"
        image_sku           = "22_04-lts-gen2"
        image_version       = "22.04.202611110"
        bootstrap_rocketmq  = true
        nsg_rules = [{
          name                       = "PrivateClients"
          priority                   = 100
          direction                  = "Inbound"
          access                     = "Allow"
          protocol                   = "Tcp"
          source_port_range          = "*"
          destination_port_range     = "9876"
          source_address_prefix      = "10.0.1.0/24"
          destination_address_prefix = "*"
        }]
      }
    }
  }
  assert {
    condition     = length(azurerm_public_ip.vm) == 0 && length(azurerm_virtual_machine_extension.linux_custom_script) == 0 && azurerm_network_interface_security_group_association.vm["rocketmq"].network_security_group_id == azurerm_network_security_group.vm["rocketmq"].id
    error_message = "RocketMQ must retain its dedicated private NIC/NSG binding without public IP or an imperative provisioner."
  }
  assert {
    condition     = length(yamldecode(base64decode(azurerm_linux_virtual_machine.vm["rocketmq"].custom_data)).runcmd) == 1 && one(azurerm_network_security_group.vm["rocketmq"].security_rule).source_address_prefix == "10.0.1.0/24"
    error_message = "The opted-in VM must receive valid cloud-init without rewriting the caller's NSG source."
  }
}

run "rocketmq_bootstrap_rejects_unpinned_image" {
  command = plan
  variables {
    vms = {
      rocketmq = {
        vm_name             = "rocketmq"
        vm_size             = "Standard_D2s_v3"
        subnet_name         = "vm"
        admin_username      = "testuser"
        ssh_public_key_path = "tests/fixtures/test.pub"
        bootstrap_rocketmq  = true
      }
    }
  }
  expect_failures = [var.vms]
}
run "original_optional_inputs_and_script_supported" {
  command = apply
  variables {
    vms = {
      jumpserver = {
        vm_name             = "jumpserver"
        vm_size             = "Standard_D2s_v5"
        subnet_name         = "vm"
        admin_username      = "testuser"
        ssh_public_key_path = "tests/fixtures/test.pub"
        custom_script       = "printf 'test-only'"
      }
    }
  }
  assert {
    condition     = contains(keys(azurerm_virtual_machine_extension.linux_custom_script), "jumpserver")
    error_message = "Existing Linux custom_script inputs must continue to provision the supported extension."
  }
  assert {
    condition     = !strcontains(output.jumpserver_details.ssh_command, " -i ") && strcontains(output.jumpserver_details.ssh_command, "testuser@10.0.1.4")
    error_message = "Omitting the optional private key path must not invent a local key path or suppress private connection details."
  }
}

run "unattached_preserves_nsg_definition_without_association" {
  command = plan
  variables {
    vms = {
      jumpserver = {
        vm_name             = "jumpserver"
        vm_size             = "Standard_D2s_v5"
        subnet_name         = "vm"
        admin_username      = "testuser"
        ssh_public_key_path = "tests/fixtures/test.pub"
        image_version       = "22.04.202611110"
        attach_nsg          = false
        nsg_rules = [{
          name                       = "OriginalSSH"
          priority                   = 100
          direction                  = "Inbound"
          access                     = "Allow"
          protocol                   = "Tcp"
          source_port_range          = "*"
          destination_port_range     = "22"
          source_address_prefix      = "*"
          destination_address_prefix = "*"
        }]
      }
    }
  }
  assert {
    condition     = length(azurerm_network_security_group.vm) == 1 && length(azurerm_network_interface_security_group_association.vm) == 0 && one(azurerm_network_security_group.vm["jumpserver"].security_rule).source_address_prefix == "*"
    error_message = "Disabling attachment must retain the NSG/rules and omit only the NIC association; company NSGs remain outside Terraform ownership."
  }
}

run "public_jumpserver_has_separate_bounded_ssh_guard" {
  command = apply
  variables {
    vms = {
      jumpserver = {
        vm_name                 = "jumpserver"
        vm_size                 = "Standard_B2s"
        subnet_name             = "vm"
        admin_username          = "testuser"
        ssh_public_key_path     = "tests/fixtures/test.pub"
        image_version           = "22.04.202611110"
        enable_public_ip        = true
        attach_nsg              = false
        protect_public_ssh      = true
        public_ssh_source_cidrs = ["203.0.113.5/32"]
      }
    }
  }
  override_resource {
    target = azurerm_network_security_group.public_ssh["jumpserver"]
    values = {
      id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/test-vm-rg/providers/Microsoft.Network/networkSecurityGroups/ssh-guard"
    }
  }
  assert {
    condition     = output.jumpserver_details.public_ip == "203.0.113.10" && output.jumpserver_details.ssh_access_status == "Configured" && azurerm_network_interface_security_group_association.vm["jumpserver"].network_security_group_id == azurerm_network_security_group.public_ssh["jumpserver"].id
    error_message = "A public jumpserver must bind a separate SSH guard, not attach its preserved original NSG."
  }
  assert {
    condition     = length([for rule in azurerm_network_security_group.public_ssh["jumpserver"].security_rule : rule if rule.access == "Allow" && rule.destination_port_range == "22" && length(rule.source_address_prefixes) == 1 && contains(rule.source_address_prefixes, "203.0.113.5/32")]) == 1
    error_message = "Only the explicitly approved management source may reach public SSH."
  }
}

run "public_jumpserver_without_approved_sources_is_deny_only" {
  command = apply
  variables {
    vms = {
      jumpserver = {
        vm_name             = "jumpserver"
        vm_size             = "Standard_B2s"
        subnet_name         = "vm"
        admin_username      = "testuser"
        ssh_public_key_path = "tests/fixtures/test.pub"
        image_version       = "22.04.202611110"
        enable_public_ip    = true
        attach_nsg          = false
        protect_public_ssh  = true
      }
    }
  }
  assert {
    condition     = one(azurerm_network_security_group.public_ssh["jumpserver"].security_rule).access == "Deny" && output.jumpserver_details.ssh_access_status == "Blocked"
    error_message = "Missing management authorization must be surfaced as Blocked, never silently open SSH to the Internet."
  }
}
