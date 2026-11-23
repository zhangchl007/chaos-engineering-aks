mock_provider "azurerm" {}
mock_provider "azapi" {}

variables {
  enabled                   = true
  name                      = "fixture"
  location                  = "uksouth"
  resource_group_id         = "/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/fixture"
  tags                      = { environment = "test" }
  scopes                    = ["/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/fixture"]
  agent_verified_target_ids = ["/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/fixture/providers/Microsoft.Compute/virtualMachines/canary"]
  scenarios = {
    cpu = {
      action_id   = "microsoft-compute-cpuPressure/1.0"
      description = "Bounded CPU configuration only."
      target_ids  = ["/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/fixture/providers/Microsoft.Compute/virtualMachines/canary"]
      parameters  = { pressureLevel = "50" }
    }
    memory = {
      action_id        = "microsoft-compute-physicalMemoryPressure/1.0"
      description      = "Bounded memory configuration only."
      target_ids       = ["/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/fixture/providers/Microsoft.Compute/virtualMachines/canary"]
      duration_minutes = 2
      parameters       = { pressureLevel = "1" }
    }
  }
}

run "disabled_pressure_has_no_resources" {
  command = plan
  variables { enabled = false }
  assert {
    condition     = length(azapi_resource.scenario) == 0 && length(azapi_resource.configuration) == 0 && length(azurerm_role_assignment.target) == 0
    error_message = "Disabled pressure configuration must not create resources or permissions."
  }
}

run "bounded_pressure_has_matching_parameter_duration" {
  command = plan
  assert {
    condition = (
      { for p in azapi_resource.scenario["cpu"].body.properties.actions[0].parameters : p.key => p.value } == { pressureLevel = "50", duration = "PT1M" } &&
      { for p in azapi_resource.scenario["memory"].body.properties.actions[0].parameters : p.key => p.value } == { pressureLevel = "1", duration = "PT2M" } &&
      azapi_resource.scenario["memory"].body.properties.actions[0].duration == "PT2M" &&
      length(azurerm_role_assignment.target) == 0
    )
    error_message = "Use actual regional parameter names and synchronized durations without automatic permissions."
  }
}

run "agent_evidence_allowlist_required" {
  command = plan
  variables { agent_verified_target_ids = [] }
  expect_failures = [azapi_resource.scenario["cpu"], azapi_resource.scenario["memory"]]
}

run "high_pressure_requires_separate_configuration_opt_in" {
  command = plan
  variables {
    scenarios = {
      cpu = {
        action_id   = "microsoft-compute-cpuPressure/1.0"
        description = "Explicit high pressure."
        target_ids  = ["/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/fixture/providers/Microsoft.Compute/virtualMachines/canary"]
        parameters  = { pressureLevel = "100" }
      }
      memory = {
        action_id   = "microsoft-compute-physicalMemoryPressure/1.0"
        description = "Explicit high pressure."
        target_ids  = ["/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/fixture/providers/Microsoft.Compute/virtualMachines/canary"]
        parameters  = { pressureLevel = "99" }
      }
    }
  }
  expect_failures = [azapi_resource.scenario["cpu"], azapi_resource.scenario["memory"]]
}

run "explicit_high_pressure_uses_catalog_bounds" {
  command = plan
  variables {
    allow_high_pressure_configuration = true
    scenarios = {
      cpu = {
        action_id   = "microsoft-compute-cpuPressure/1.0"
        description = "Explicit high pressure."
        target_ids  = ["/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/fixture/providers/Microsoft.Compute/virtualMachines/canary"]
        parameters  = { pressureLevel = "100" }
      }
      memory = {
        action_id   = "microsoft-compute-physicalMemoryPressure/1.0"
        description = "Explicit high pressure."
        target_ids  = ["/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/fixture/providers/Microsoft.Compute/virtualMachines/canary"]
        parameters  = { pressureLevel = "99" }
      }
    }
  }
  assert {
    condition     = length(azapi_resource.configuration) == 2
    error_message = "Explicit opt-in may configure, but never execute, catalog-bounded pressure."
  }
}

run "invalid_pressure_and_parameter_shapes_rejected" {
  command = plan
  variables {
    allow_high_pressure_configuration = true
    scenarios = {
      cpu_overflow = {
        action_id   = "microsoft-compute-cpuPressure/1.0"
        description = "Invalid."
        target_ids  = ["/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/fixture/providers/Microsoft.Compute/virtualMachines/canary"]
        parameters  = { pressureLevel = "101" }
      }
      memory_overflow = {
        action_id   = "microsoft-compute-physicalMemoryPressure/1.0"
        description = "Invalid."
        target_ids  = ["/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/fixture/providers/Microsoft.Compute/virtualMachines/canary"]
        parameters  = { pressureLevel = "100" }
      }
      fractional = {
        action_id   = "microsoft-compute-cpuPressure/1.0"
        description = "Invalid."
        target_ids  = ["/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/fixture/providers/Microsoft.Compute/virtualMachines/canary"]
        parameters  = { pressureLevel = "50.5" }
      }
      missing = {
        action_id   = "microsoft-compute-cpuPressure/1.0"
        description = "Invalid."
        target_ids  = ["/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/fixture/providers/Microsoft.Compute/virtualMachines/canary"]
      }
      wrong_case = {
        action_id   = "microsoft-compute-cpuPressure/1.0"
        description = "Invalid."
        target_ids  = ["/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/fixture/providers/Microsoft.Compute/virtualMachines/canary"]
        parameters  = { PressureLevel = "50" }
      }
      extra_duration = {
        action_id   = "microsoft-compute-cpuPressure/1.0"
        description = "Invalid."
        target_ids  = ["/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/fixture/providers/Microsoft.Compute/virtualMachines/canary"]
        parameters  = { pressureLevel = "50", duration = "PT10M" }
      }
      zero = {
        action_id   = "microsoft-compute-physicalMemoryPressure/1.0"
        description = "Invalid."
        target_ids  = ["/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/fixture/providers/Microsoft.Compute/virtualMachines/canary"]
        parameters  = { pressureLevel = "0" }
      }
      non_numeric = {
        action_id   = "microsoft-compute-cpuPressure/1.0"
        description = "Invalid."
        target_ids  = ["/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/fixture/providers/Microsoft.Compute/virtualMachines/canary"]
        parameters  = { pressureLevel = "NaN" }
      }
    }
  }
  expect_failures = [
    azapi_resource.scenario["cpu_overflow"], azapi_resource.scenario["memory_overflow"],
    azapi_resource.scenario["fractional"], azapi_resource.scenario["missing"],
    azapi_resource.scenario["wrong_case"], azapi_resource.scenario["extra_duration"],
    azapi_resource.scenario["zero"], azapi_resource.scenario["non_numeric"]
  ]
}

run "vmss_and_multiple_vm_pressure_rejected" {
  command = plan
  variables {
    scenarios = {
      vmss = {
        action_id   = "microsoft-compute-cpuPressure/1.0"
        description = "No verified per-instance VMSS boundary."
        target_ids  = ["/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/fixture/providers/Microsoft.Compute/virtualMachineScaleSets/pool"]
        parameters  = { pressureLevel = "50" }
      }
      multiple = {
        action_id   = "microsoft-compute-cpuPressure/1.0"
        description = "Too many VMs."
        target_ids = [
          "/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/fixture/providers/Microsoft.Compute/virtualMachines/canary",
          "/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/fixture/providers/Microsoft.Compute/virtualMachines/other"
        ]
        parameters = { pressureLevel = "50" }
      }
    }
  }
  expect_failures = [azapi_resource.scenario["vmss"], azapi_resource.scenario["multiple"]]
}

run "agent_scope_cannot_be_a_subscription" {
  command = plan
  variables {
    enabled                   = false
    agent_verified_target_ids = ["/subscriptions/00000000-0000-0000-0000-000000000001"]
  }
  expect_failures = [var.agent_verified_target_ids]
}
