# Copyright (c) HashiCorp, Inc.
# SPDX-License-Identifier: MPL-2.0

terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "4.55.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "3.7.2"
    }
    azapi = {
      source  = "Azure/azapi"
      version = "2.14.0"
    }
  }

  required_version = ">= 1.9, < 2.0"

  # Optional Azure backend: enable the environments/azurerm-backend_override.tf.example override.
  backend "local" {
    path = "local-state/dev/platform.tfstate"
  }
}