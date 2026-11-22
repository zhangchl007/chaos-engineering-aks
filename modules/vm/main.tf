locals {
  global_tags = merge(
    { for key, value in {
      Environment = var.env_prefix
      ManagedBy   = "Terraform"
      Component   = "vm"
    } : key => value if !contains([for tag_key in keys(var.tags) : lower(tag_key)], lower(key)) },
    var.tags
  )
  vm_tags = {
    for name, config in var.vms : name => merge(
      { for key, value in local.global_tags : key => value if !contains([for tag_key in keys(config.tags) : lower(tag_key)], lower(key)) },
      config.tags
    )
  }
}

# Public IPs for VMs (optional)
resource "azurerm_public_ip" "vm" {
  for_each = {
    for name, config in var.vms : name => config
    if config.enable_public_ip
  }

  name                = "${var.env_prefix}-${each.value.vm_name}-pip"
  location            = var.location
  resource_group_name = var.resource_group_name
  allocation_method   = "Static"
  sku                 = "Standard"
  tags                = local.vm_tags[each.key]
}

# Network Security Groups
resource "azurerm_network_security_group" "vm" {
  for_each = var.vms

  name                = "${var.env_prefix}-${each.value.vm_name}-nsg"
  location            = var.location
  resource_group_name = var.resource_group_name
  tags                = local.vm_tags[each.key]

  # Default security rules
  dynamic "security_rule" {
    for_each = each.value.nsg_rules
    content {
      name                       = security_rule.value.name
      priority                   = security_rule.value.priority
      direction                  = security_rule.value.direction
      access                     = security_rule.value.access
      protocol                   = security_rule.value.protocol
      source_port_range          = security_rule.value.source_port_range
      destination_port_range     = security_rule.value.destination_port_range
      source_address_prefix      = security_rule.value.source_address_prefix
      destination_address_prefix = security_rule.value.destination_address_prefix
    }
  }
}

resource "azurerm_network_security_group" "public_ssh" {
  for_each = { for name, config in var.vms : name => config if config.protect_public_ssh }

  name                = "${var.env_prefix}-${each.value.vm_name}-ssh-access-nsg"
  location            = var.location
  resource_group_name = var.resource_group_name
  tags                = local.vm_tags[each.key]

  dynamic "security_rule" {
    for_each = length(each.value.public_ssh_source_cidrs) > 0 ? [each.value.public_ssh_source_cidrs] : []
    content {
      name                       = "AllowApprovedSSH"
      priority                   = 100
      direction                  = "Inbound"
      access                     = "Allow"
      protocol                   = "Tcp"
      source_port_range          = "*"
      destination_port_range     = "22"
      source_address_prefixes    = security_rule.value
      destination_address_prefix = "*"
    }
  }

  security_rule {
    name                       = "DenyOtherInbound"
    priority                   = 4096
    direction                  = "Inbound"
    access                     = "Deny"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }
}

# Network Interfaces
resource "azurerm_network_interface" "vm" {
  for_each = var.vms

  name                = "${var.env_prefix}-${each.value.vm_name}-nic"
  location            = var.location
  resource_group_name = var.resource_group_name
  tags                = local.vm_tags[each.key]

  ip_configuration {
    name                          = "${each.value.vm_name}-ip-config"
    subnet_id                     = var.subnet_ids[each.value.subnet_name]
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = each.value.enable_public_ip ? azurerm_public_ip.vm[each.key].id : null
  }
}

# Associate NSGs with NICs
resource "azurerm_network_interface_security_group_association" "vm" {
  for_each = { for name, config in var.vms : name => config if config.attach_nsg || config.protect_public_ssh }

  network_interface_id      = azurerm_network_interface.vm[each.key].id
  network_security_group_id = each.value.protect_public_ssh ? azurerm_network_security_group.public_ssh[each.key].id : azurerm_network_security_group.vm[each.key].id
}

# Linux Virtual Machines
resource "azurerm_linux_virtual_machine" "vm" {
  for_each = {
    for name, config in var.vms : name => config
    if lower(config.os_type) == "linux"
  }

  name                = "${var.env_prefix}-${each.value.vm_name}"
  location            = var.location
  resource_group_name = var.resource_group_name
  size                = each.value.vm_size

  admin_username                  = each.value.admin_username
  disable_password_authentication = true

  admin_ssh_key {
    username   = each.value.admin_username
    public_key = file(pathexpand(each.value.ssh_public_key_path))
  }

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Premium_LRS"
  }

  source_image_reference {
    publisher = each.value.image_publisher
    offer     = each.value.image_offer
    sku       = each.value.image_sku
    version   = each.value.image_version
  }

  network_interface_ids = [
    azurerm_network_interface.vm[each.key].id,
  ]

  custom_data = each.value.bootstrap_rocketmq ? base64encode(templatefile(
    "${path.module}/templates/rocketmq-cloud-init.yaml.tftpl",
    { bootstrap_script = file("${path.module}/scripts/rocketmq-bootstrap.sh") }
  )) : null

  tags = local.vm_tags[each.key]

  depends_on = [azurerm_network_interface_security_group_association.vm]
}

# Windows Virtual Machines
resource "azurerm_windows_virtual_machine" "vm" {
  for_each = {
    for name, config in var.vms : name => config
    if lower(config.os_type) == "windows"
  }

  name                = "${var.env_prefix}-${each.value.vm_name}"
  location            = var.location
  resource_group_name = var.resource_group_name
  size                = each.value.vm_size

  admin_username = each.value.admin_username
  admin_password = random_password.vm_password[each.key].result

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Premium_LRS"
  }

  source_image_reference {
    publisher = each.value.image_publisher
    offer     = each.value.image_offer
    sku       = each.value.image_sku
    version   = each.value.image_version
  }

  network_interface_ids = [
    azurerm_network_interface.vm[each.key].id,
  ]

  tags = local.vm_tags[each.key]

  depends_on = [azurerm_network_interface_security_group_association.vm]
}

# Generate random passwords for Windows VMs
resource "random_password" "vm_password" {
  for_each = {
    for name, config in var.vms : name => config
    if lower(config.os_type) == "windows"
  }

  length      = 16
  special     = true
  min_lower   = 1
  min_upper   = 1
  min_numeric = 1
}

resource "azurerm_virtual_machine_extension" "linux_custom_script" {
  for_each = {
    for name, config in var.vms : name => config
    if lower(config.os_type) == "linux" && config.custom_script != ""
  }

  name                 = "${each.value.vm_name}-custom-script"
  virtual_machine_id   = azurerm_linux_virtual_machine.vm[each.key].id
  publisher            = "Microsoft.Azure.Extensions"
  type                 = "CustomScript"
  type_handler_version = "2.0"

  settings = jsonencode({
    commandToExecute = each.value.custom_script
  })
}
