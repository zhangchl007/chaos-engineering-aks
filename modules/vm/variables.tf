variable "resource_group_name" {
  description = "Resource group name"
  type        = string
}

variable "location" {
  description = "Azure region"
  type        = string
}

variable "env_prefix" {
  description = "Environment prefix for naming"
  type        = string
}

variable "vnet_id" {
  description = "Virtual Network ID"
  type        = string
}

variable "subnet_ids" {
  description = "Subnet IDs map from vnet module"
  type        = map(string)
}

variable "vms" {
  description = "Map of VMs to create with custom configuration"
  type = map(object({
    vm_name                 = string
    vm_size                 = string
    subnet_name             = string
    admin_username          = string
    ssh_public_key_path     = string
    ssh_private_key_path    = optional(string, "")
    os_type                 = optional(string, "linux")
    image_publisher         = optional(string, "Canonical")
    image_offer             = optional(string, "0001-com-ubuntu-server-focal")
    image_sku               = optional(string, "20_04-lts-gen2")
    image_version           = optional(string, "latest")
    enable_public_ip        = optional(bool, false)
    attach_nsg              = optional(bool, true)
    protect_public_ssh      = optional(bool, false)
    public_ssh_source_cidrs = optional(list(string), [])
    bootstrap_rocketmq      = optional(bool, false)
    nsg_rules = optional(list(object({
      name                       = string
      priority                   = number
      direction                  = string
      access                     = string
      protocol                   = string
      source_port_range          = string
      destination_port_range     = string
      source_address_prefix      = string
      destination_address_prefix = string
    })), [])
    custom_script = optional(string, "")
    tags          = optional(map(string), {})
  }))
  default = {}

  validation {
    condition     = alltrue([for vm in var.vms : length(vm.tags) == length(distinct([for key in keys(vm.tags) : lower(key)]))])
    error_message = "Azure tag names are case-insensitive; each VM's tags must not contain keys that differ only by case."
  }

  validation {
    condition = alltrue([
      for vm in var.vms : contains(["linux", "windows"], lower(vm.os_type)) &&
      (vm.image_version == "latest" || can(regex("^[0-9]+\\.[0-9]+\\.[0-9]+$", vm.image_version)))
    ])
    error_message = "OS must be linux or windows and image_version must be latest or an explicit numeric Azure image version. Verify pinned image availability in the target region."
  }

  validation {
    condition = alltrue([
      for vm in var.vms : lower(vm.os_type) != "linux" || trimspace(vm.ssh_public_key_path) != ""
    ])
    error_message = "Linux VMs require the existing explicit public SSH key path. The optional private key path is used only in connection instructions."
  }
  validation {
    condition = alltrue([
      for vm in var.vms : !vm.bootstrap_rocketmq || (
        lower(vm.os_type) == "linux" && vm.image_publisher == "Canonical" &&
        vm.image_offer == "0001-com-ubuntu-server-jammy" && vm.image_sku == "22_04-lts-gen2" &&
        vm.image_version != "latest" && !vm.enable_public_ip && vm.custom_script == ""
      )
    ])
    error_message = "RocketMQ bootstrap requires a pinned Canonical Ubuntu 22.04 Gen2 Linux image, private networking, and no competing custom_script."
  }
  validation {
    condition = alltrue([
      for vm in var.vms : !vm.protect_public_ssh || (
        vm.enable_public_ip && lower(vm.os_type) == "linux" && alltrue([
          for source in vm.public_ssh_source_cidrs :
          can(cidrnetmask(source)) && try(tonumber(split("/", source)[1]) >= 24, false)
        ])
      )
    ])
    error_message = "Public SSH protection requires a public Linux VM and approved /24-or-narrower sources; an empty list denies all inbound traffic."
  }
}

variable "tags" {
  description = "Tags to apply to VM resources"
  type        = map(string)
  default     = {}
  validation {
    condition     = length(var.tags) == length(distinct([for key in keys(var.tags) : lower(key)]))
    error_message = "Azure tag names are case-insensitive; tags must not contain keys that differ only by case."
  }
}