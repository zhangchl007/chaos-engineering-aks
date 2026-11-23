mock_provider "azurerm" {}
mock_provider "azapi" {}

variables {
  subscription_id   = "00000000-0000-0000-0000-000000000000"
  tenant_id         = "00000000-0000-0000-0000-000000000000"
  resource_group_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/test"
  name              = "test-workspace"
  location          = "northeurope"
}

run "supported_workspace_region" {
  command = plan
}

run "target_region_is_not_workspace_region" {
  command = plan
  variables {
    location = "uaenorth"
  }
  expect_failures = [var.location]
}

run "pod_configuration_is_forwarded" {
  command = plan
  variables {
    enabled = true
    scopes  = ["/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/test"]
    aks_extensions = {
      canary = {
        cluster_id             = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/test/providers/Microsoft.ContainerService/managedClusters/test"
        target_namespaces      = ["chaos-targets"]
        compatibility_verified = true
      }

    }
    pod_scenarios = {
      canary-pod-delete = {
        description   = "test"
        extension_key = "canary"
        namespace     = "chaos-targets"
        labels        = { app = "checkout-canary", chaos-canary = "target" }
      }
    }
  }
  assert {
    condition     = keys(output.configuration_ids) == ["canary-pod-delete"]
    error_message = "The Chaos stack must forward installation/Scenario inputs and expose the pod configuration without a service-direct definition."
  }
}

run "pressure_qualification_and_high_policy_are_forwarded" {
  command = plan
  variables {
    enabled                           = true
    scopes                            = ["/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/test"]
    agent_verified_target_ids         = ["/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/test/providers/Microsoft.Compute/virtualMachines/canary"]
    allow_high_pressure_configuration = true
    scenarios = {
      memory = {
        action_id   = "microsoft-compute-physicalMemoryPressure/1.0"
        description = "Configuration forwarding only."
        target_ids  = ["/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/test/providers/Microsoft.Compute/virtualMachines/canary"]
        parameters  = { pressureLevel = "99" }
      }
    }
  }
  assert {
    condition     = keys(output.configuration_ids) == ["memory"]
    error_message = "Both pressure safety inputs must reach the module without relaxing its defaults."
  }
}
