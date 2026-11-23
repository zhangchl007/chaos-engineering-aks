locals {
  pod_action_ids = {
    pod_delete          = "urn:csci:microsoft:containerservice:poddelete/1.0.0"
    pod_cpu_hog         = "urn:csci:microsoft:containerservice:podcpuhog/1.0.0"
    pod_memory_hog      = "urn:csci:microsoft:containerservice:podmemoryhog/1.0.0"
    pod_network_latency = "urn:csci:microsoft:containerservice:podnetworklatency/1.0.0"
    pod_network_loss    = "urn:csci:microsoft:containerservice:podnetworkloss/1.0.0"
  }
  pod_parameters = {
    for key, s in var.pod_scenarios : key => merge(
      {
        namespace              = s.namespace
        labelSelector          = join(",", [for label in sort(keys(s.labels)) : "${label}=${s.labels[label]}"])
        appKind                = s.app_kind
        durationSeconds        = tostring(s.duration_seconds)
        podsAffectedPercentage = tostring(s.pods_affected_percentage)
      },
      s.fault == "pod_delete" ? { force = "false", chaosIntervalSeconds = tostring(s.chaos_interval_seconds) } : {},
      s.target_container == null ? {} : { targetContainer = s.target_container },
      s.fault == "pod_cpu_hog" ? { cpuCores = tostring(s.cpu_cores) } : {},
      s.fault == "pod_memory_hog" ? { memoryConsumptionMegabytes = tostring(s.memory_megabytes) } : {},
      s.fault == "pod_network_latency" ? { latencyMilliseconds = tostring(s.latency_milliseconds), jitterMilliseconds = "0", sequence = "serial" } : {},
      s.fault == "pod_network_loss" ? { packetLossPercentage = tostring(s.packet_loss_percentage), sequence = "serial" } : {}
    )
  }
}

resource "azapi_resource" "pod_scenario" {
  for_each  = var.enabled ? var.pod_scenarios : {}
  type      = "Microsoft.Chaos/workspaces/scenarios@${local.api_version}"
  name      = each.key
  parent_id = azapi_resource.workspace[0].id
  body = {
    properties = {
      description = each.value.description
      parameters = [{
        name        = "aksClusterId"
        type        = "String"
        description = "Explicit operator-approved AKS cluster."
        required    = true
      }]
      actions = [{
        name        = "bounded-pod-fault"
        actionId    = lookup(local.pod_action_ids, each.value.fault, "")
        description = each.value.description
        duration    = "PT1M"
        externalResource = {
          # Split the token to preserve both percent signs through HCL template escaping.
          resourceId = join("", ["%%", "{parameters.aksClusterId}%%"])
        }
        parameters = [for key, value in local.pod_parameters[each.key] : { key = key, value = value }]
      }]
    }
  }
  lifecycle {
    precondition {
      condition = try(
        var.aks_extensions[each.value.extension_key].compatibility_verified &&
        contains(var.aks_extensions[each.value.extension_key].target_namespaces, each.value.namespace),
        false
      )
      error_message = "Pod Scenarios require a referenced operator installation with verified non-production compatibility and namespace membership."
    }
    precondition {
      condition = !contains(["pod_network_latency", "pod_network_loss"], each.value.fault) || try(
        var.aks_extensions[each.value.extension_key].network_faults_enabled, false
      )
      error_message = "Network pod Actions require the verified extension network component and an approved residual-effect recovery procedure."
    }
  }
}

resource "azapi_resource" "pod_configuration" {
  for_each  = var.enabled ? var.pod_scenarios : {}
  type      = "Microsoft.Chaos/workspaces/scenarios/configurations@${local.api_version}"
  name      = "approved-targets"
  parent_id = azapi_resource.pod_scenario[each.key].id
  body = {
    properties = {
      scenarioId = azapi_resource.pod_scenario[each.key].id
      parameters = [{
        key   = "aksClusterId"
        value = try(var.aks_extensions[each.value.extension_key].cluster_id, "")
      }]
      resourceTargeting = {
        include = { resources = [try(var.aks_extensions[each.value.extension_key].cluster_id, "")] }
        exclude = local.targeting_exclusions
      }
    }
  }
  lifecycle {
    # API GET normalizes this redundant parent reference to its name.
    ignore_changes = [body.properties.scenarioId]
    postcondition {
      condition     = contains([lower(each.key), lower(self.parent_id)], lower(self.body.properties.scenarioId))
      error_message = "The pod configuration must reference its actual parent Scenario, as an ARM ID or the API-normalized name."
    }
  }
}
