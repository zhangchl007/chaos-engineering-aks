mock_provider "azurerm" {}
mock_provider "azapi" {}

variables {
  enabled           = true
  name              = "fixture"
  location          = "northeurope"
  resource_group_id = "/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/fixture"
  scopes            = ["/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/fixture"]
  tags              = { environment = "test" }
  aks_extensions = {
    canary = {
      cluster_id             = "/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/fixture/providers/Microsoft.ContainerService/managedClusters/test"
      target_namespaces      = ["chaos-targets"]
      compatibility_verified = true
    }
  }
  pod_scenarios = {
    pod-delete = {
      description   = "Delete only the approved canary."
      extension_key = "canary"
      namespace     = "chaos-targets"
      labels        = { app = "checkout-canary", chaos-canary = "target" }
    }
  }
}

run "pod_binding_and_containment" {
  command = plan
  assert {
    condition = (
      azapi_resource.pod_scenario["pod-delete"].body.properties.actions[0].externalResource.resourceId == join("", ["%%", "{parameters.aksClusterId}%%"]) &&
      azapi_resource.pod_configuration["pod-delete"].body.properties.parameters[0].value == var.aks_extensions["canary"].cluster_id &&
      azapi_resource.pod_configuration["pod-delete"].body.properties.resourceTargeting.include.resources == [var.aks_extensions["canary"].cluster_id] &&
      azapi_resource.pod_scenario["pod-delete"].body.properties.actions[0].duration == "PT1M"
    )
    error_message = "Pod Actions must preserve the external binding token and supply the exact allowlisted cluster."
  }
  assert {
    condition = (
      contains(azapi_resource.pod_scenario["pod-delete"].body.properties.actions[0].parameters, { key = "labelSelector", value = "app=checkout-canary,chaos-canary=target" }) &&
      contains(azapi_resource.pod_scenario["pod-delete"].body.properties.actions[0].parameters, { key = "force", value = "false" }) &&
      length(azurerm_role_assignment.target) == 0 && length(azurerm_role_definition.target) == 0
    )
    error_message = "Generate exact AND selectors and graceful deletion; do not take over extension runtime permissions."
  }
}

run "disabled_pods_create_no_configuration_or_identity" {
  command = plan
  variables { enabled = false }
  assert {
    condition = (
      length(azapi_resource.pod_scenario) == 0 && length(azapi_resource.pod_configuration) == 0 &&
      length(azurerm_user_assigned_identity.runtime) == 0 && length(azurerm_role_assignment.discovery) == 0
    )
    error_message = "The existing default-off switch must include pod configuration and its permissions."
  }
}

run "missing_installation_rejected" {
  command = plan
  variables { aks_extensions = {} }
  expect_failures = [azapi_resource.pod_scenario["pod-delete"]]
}

run "namespace_not_installed_rejected" {
  command = plan
  variables {
    aks_extensions = {
      canary = {
        cluster_id             = "/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/fixture/providers/Microsoft.ContainerService/managedClusters/test"
        target_namespaces      = ["other-targets"]
        compatibility_verified = true
      }
    }
  }
  expect_failures = [azapi_resource.pod_scenario["pod-delete"]]
}

run "unverified_private_cluster_rejected" {
  command = plan
  variables {
    aks_extensions = {
      canary = {
        cluster_id        = "/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/fixture/providers/Microsoft.ContainerService/managedClusters/test"
        target_namespaces = ["chaos-targets"]
      }
    }
  }
  expect_failures = [azapi_resource.pod_scenario["pod-delete"]]
}

run "verification_namespace_rejected" {
  command = plan
  variables {
    pod_scenarios = {
      pod-delete = {
        description   = "test"
        extension_key = "canary"
        namespace     = "chaos-validation"
        labels        = { app = "checkout-canary", chaos-canary = "target" }
      }
    }
  }
  expect_failures = [var.pod_scenarios]
}

run "selector_expression_rejected" {
  command = plan
  variables {
    pod_scenarios = {
      pod-delete = {
        description   = "test"
        extension_key = "canary"
        namespace     = "chaos-targets"
        labels        = { app = "checkout,other", chaos-canary = "target" }
      }
    }
  }
  expect_failures = [var.pod_scenarios]
}

run "unbounded_impact_rejected" {
  command = plan
  variables {
    pod_scenarios = {
      pod-delete = {
        description              = "test"
        extension_key            = "canary"
        namespace                = "chaos-targets"
        labels                   = { app = "checkout-canary", chaos-canary = "target" }
        duration_seconds         = 61
        pods_affected_percentage = 100
      }
    }
  }
  expect_failures = [var.pod_scenarios]
}

run "excluded_cluster_rejected" {
  command = plan
  variables {
    excluded_resource_ids = ["/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/fixture/providers/Microsoft.ContainerService/managedClusters/test"]
  }
  expect_failures = [azapi_resource.workspace[0]]
}

run "network_component_required" {
  command = plan
  variables {
    pod_scenarios = {
      pod-delete = {
        description            = "test"
        extension_key          = "canary"
        namespace              = "chaos-targets"
        labels                 = { app = "checkout-canary", chaos-canary = "target" }
        fault                  = "pod_network_loss"
        packet_loss_percentage = 5
      }
    }
  }
  expect_failures = [azapi_resource.pod_scenario["pod-delete"]]
}

run "stress_without_tools_rejected" {
  command = plan
  variables {
    pod_scenarios = {
      pod-delete = {
        description      = "test"
        extension_key    = "canary"
        namespace        = "chaos-targets"
        labels           = { app = "checkout-canary", chaos-canary = "target" }
        fault            = "pod_cpu_hog"
        target_container = "application"
        cpu_cores        = 1
      }
    }
  }
  expect_failures = [var.pod_scenarios]
}

run "bounded_stress_and_network_parameters" {
  command = plan
  variables {
    aks_extensions = {
      canary = {
        cluster_id             = "/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/fixture/providers/Microsoft.ContainerService/managedClusters/test"
        target_namespaces      = ["chaos-targets"]
        compatibility_verified = true
        network_faults_enabled = true
      }
    }
    pod_scenarios = {
      cpu = {
        description              = "test"
        extension_key            = "canary"
        namespace                = "chaos-targets"
        labels                   = { app = "checkout-canary", chaos-canary = "target" }
        fault                    = "pod_cpu_hog"
        target_container         = "application"
        container_tools_verified = true
        cpu_cores                = 1
      }
      memory = {
        description              = "test"
        extension_key            = "canary"
        namespace                = "chaos-targets"
        labels                   = { app = "checkout-canary", chaos-canary = "target" }
        fault                    = "pod_memory_hog"
        target_container         = "application"
        container_tools_verified = true
        memory_megabytes         = 32
      }
      latency = {
        description          = "test"
        extension_key        = "canary"
        namespace            = "chaos-targets"
        labels               = { app = "checkout-canary", chaos-canary = "target" }
        fault                = "pod_network_latency"
        latency_milliseconds = 100
      }
      loss = {
        description            = "test"
        extension_key          = "canary"
        namespace              = "chaos-targets"
        labels                 = { app = "checkout-canary", chaos-canary = "target" }
        fault                  = "pod_network_loss"
        packet_loss_percentage = 5
      }
    }
  }
  assert {
    condition = (
      contains(azapi_resource.pod_scenario["cpu"].body.properties.actions[0].parameters, { key = "cpuCores", value = "1" }) &&
      contains(azapi_resource.pod_scenario["memory"].body.properties.actions[0].parameters, { key = "memoryConsumptionMegabytes", value = "32" }) &&
      contains(azapi_resource.pod_scenario["latency"].body.properties.actions[0].parameters, { key = "latencyMilliseconds", value = "100" }) &&
      contains(azapi_resource.pod_scenario["loss"].body.properties.actions[0].parameters, { key = "packetLossPercentage", value = "5" }) &&
      contains(azapi_resource.pod_scenario["loss"].body.properties.actions[0].parameters, { key = "sequence", value = "serial" })
    )
    error_message = "Pressure and network Actions must use explicit bounded string parameters, never unsafe service defaults."
  }
}

run "scenario_name_collision_rejected" {
  command = plan
  variables {
    scenarios = {
      Pod-Delete = {
        action_id   = "microsoft-mysql-restart/1.0"
        description = "test"
        target_ids  = ["/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/fixture/providers/Microsoft.DBforMySQL/flexibleServers/test"]
      }
    }
  }
  expect_failures = [azapi_resource.workspace[0]]
}
