terraform {
  required_providers {
    azurerm = { source = "hashicorp/azurerm" }
    azapi   = { source = "Azure/azapi" }
  }
}

locals {
  api_version = "2026-08-01-preview"
  catalog = {
    "microsoft-mysql-failover/1.0"                     = "Microsoft.DBforMySQL/flexibleServers"
    "microsoft-mysql-restart/1.0"                      = "Microsoft.DBforMySQL/flexibleServers"
    "microsoft-azurepostgresql-failover/1.0"           = "Microsoft.DBforPostgreSQL/flexibleServers"
    "microsoft-azureclusteredcacheforredis-reboot/1.0" = "Microsoft.Cache/redis"
    "microsoft-managedredis-flushdatabase/1.0"         = "Microsoft.Cache/redisEnterprise"
    "microsoft-managedredis-forceunlink/1.0"           = "Microsoft.Cache/redisEnterprise"
    "microsoft-documentdb-offlineregion/1.0"           = "Microsoft.DocumentDB/databaseAccounts"
    "microsoft-eventhub-changeeventhubstate/1.0"       = "Microsoft.EventHub/namespaces"
    "microsoft-servicebus-changequeuestate/1.0"        = "Microsoft.ServiceBus/namespaces"
    "microsoft-servicebus-changetopicstate/1.0"        = "Microsoft.ServiceBus/namespaces"
    "microsoft-servicebus-changesubscriptionstate/1.0" = "Microsoft.ServiceBus/namespaces"
    "microsoft-storageaccount-plannedfailover/1.0"     = "Microsoft.Storage/storageAccounts"
    "microsoft-virtualmachinescaleset-shutdown/1.0"    = "Microsoft.Compute/virtualMachineScaleSets"
    "microsoft-compute-restart/1.0"                    = "Microsoft.Compute/virtualMachines"
  }
  destructive = toset([
    "microsoft-managedredis-flushdatabase/1.0",
    "microsoft-managedredis-forceunlink/1.0",
    "microsoft-storageaccount-plannedfailover/1.0",
    "microsoft-servicebus-changetopicstate/1.0",
    "microsoft-servicebus-changesubscriptionstate/1.0"
  ])
  service_targets = toset([for id in flatten([for s in var.scenarios : tolist(s.target_ids)]) : lower(id)])
  pod_targets = toset([
    for key, extension in var.aks_extensions : lower(extension.cluster_id)
    if contains([for s in var.pod_scenarios : s.extension_key], key)
  ])
  targets  = setunion(local.service_targets, local.pod_targets)
  excluded = toset([for id in var.excluded_resource_ids : lower(id)])
  targeting_exclusions = {
    resources = sort(tolist(var.excluded_resource_ids))
    tags = [
      { key = "environment", value = "production" },
      { key = "environment", value = "prod" },
      { key = "chaos-excluded", value = "true" }
    ]
  }
}

resource "azurerm_user_assigned_identity" "runtime" {
  count               = var.enabled ? 1 : 0
  name                = "${var.name}-runtime"
  location            = var.location
  resource_group_name = split("/", var.resource_group_id)[4]
  tags                = var.tags
}

resource "azapi_resource" "workspace" {
  count     = var.enabled ? 1 : 0
  type      = "Microsoft.Chaos/workspaces@${local.api_version}"
  name      = var.name
  parent_id = var.resource_group_id
  location  = var.location
  tags      = var.tags
  identity {
    type         = "UserAssigned"
    identity_ids = [azurerm_user_assigned_identity.runtime[0].id]
  }
  body = {
    properties = { scopes = sort(tolist(var.scopes)) }
  }
  lifecycle {
    precondition {
      condition     = length(var.scopes) > 0
      error_message = "An enabled Workspace requires explicit non-production discovery scopes."
    }
    precondition {
      condition     = alltrue([for id in local.targets : anytrue([for scope in var.scopes : startswith(lower(id), "${lower(scope)}/providers/")])])
      error_message = "Every target must belong to an approved discovery scope."
    }
    precondition {
      condition     = length(setintersection(local.targets, local.excluded)) == 0
      error_message = "Excluded resources cannot also be approved targets."
    }
    precondition {
      condition     = contains(["dev", "test"], lookup(var.tags, "environment", ""))
      error_message = "Workspace configuration requires explicit dev/test environment metadata."
    }
    precondition {
      condition     = length(distinct([for key in concat(keys(var.scenarios), keys(var.pod_scenarios)) : lower(key)])) == length(var.scenarios) + length(var.pod_scenarios)
      error_message = "Service-direct and pod Scenarios must have distinct names in the Workspace."
    }
  }
}

resource "azurerm_role_assignment" "discovery" {
  for_each             = var.enabled ? var.scopes : toset([])
  scope                = each.value
  role_definition_name = "Reader"
  principal_id         = azurerm_user_assigned_identity.runtime[0].principal_id
}

resource "azurerm_role_definition" "target" {
  for_each = var.enabled ? var.permissions : {}
  name     = "${var.name}-${each.key}"
  scope    = regex("(?i)^/subscriptions/[^/]+/resourceGroups/[^/]+", each.value.target_id)
  permissions {
    actions      = sort(tolist(each.value.actions))
    data_actions = sort(tolist(each.value.data_actions))
  }
  assignable_scopes = [regex("(?i)^/subscriptions/[^/]+/resourceGroups/[^/]+", each.value.target_id)]
  lifecycle {
    precondition {
      condition     = contains(local.service_targets, lower(each.value.target_id))
      error_message = "Custom runtime permissions can only be assigned to service-direct targets; the extension installer owns pod runtime permissions."
    }
  }
}

resource "azurerm_role_assignment" "target" {
  for_each           = var.enabled ? var.permissions : {}
  scope              = each.value.target_id
  role_definition_id = azurerm_role_definition.target[each.key].role_definition_resource_id
  principal_id       = azurerm_user_assigned_identity.runtime[0].principal_id
}

resource "azapi_resource" "scenario" {
  for_each  = var.enabled ? var.scenarios : {}
  type      = "Microsoft.Chaos/workspaces/scenarios@${local.api_version}"
  name      = each.key
  parent_id = azapi_resource.workspace[0].id
  body = {
    properties = {
      description = each.value.description
      parameters  = []
      actions = [{
        name        = "bounded-fault"
        actionId    = each.value.action_id
        description = each.value.description
        duration    = "PT${each.value.duration_minutes}M"
        parameters  = [for key, value in each.value.parameters : { key = key, value = value }]
      }]
    }
  }
  lifecycle {
    precondition {
      condition     = contains(keys(local.catalog), each.value.action_id)
      error_message = "Select an explicitly supported service-direct Action; extension/agent Actions require separate verified integration."
    }
    precondition {
      condition     = var.allow_destructive_configuration || !contains(local.destructive, each.value.action_id)
      error_message = "Destructive configuration requires an explicit opt-in and recovery plan."
    }
    precondition {
      condition     = alltrue([for id in each.value.target_ids : can(regex("^/subscriptions/[^/]+/resourcegroups/[^/]+/providers/${replace(lower(lookup(local.catalog, each.value.action_id, "unsupported")), ".", "\\.")}/[^/]+$", lower(id)))])
      error_message = "The actual target resource type must match the selected Action."
    }
    precondition {
      condition = (alltrue([for key, value in each.value.parameters : trimspace(value) != ""]) &&
        (each.value.action_id != "microsoft-mysql-failover/1.0" || contains(keys(each.value.parameters), "RestoreOnStop")) &&
        (each.value.action_id != "microsoft-azurepostgresql-failover/1.0" || contains(keys(each.value.parameters), "FailoverMode")) &&
        (each.value.action_id != "microsoft-azureclusteredcacheforredis-reboot/1.0" || contains(keys(each.value.parameters), "RebootType")) &&
        (each.value.action_id != "microsoft-documentdb-offlineregion/1.0" || contains(keys(each.value.parameters), "RegionName")) &&
        (!startswith(each.value.action_id, "microsoft-servicebus-") || contains(keys(each.value.parameters), "desiredState")) &&
        (each.value.action_id != "microsoft-servicebus-changequeuestate/1.0" || contains(keys(each.value.parameters), "queues")) &&
        (each.value.action_id != "microsoft-servicebus-changetopicstate/1.0" || contains(keys(each.value.parameters), "topics")) &&
        (each.value.action_id != "microsoft-servicebus-changesubscriptionstate/1.0" || alltrue([for k in ["topic", "subscriptions"] : contains(keys(each.value.parameters), k)])) &&
        (each.value.action_id != "microsoft-eventhub-changeeventhubstate/1.0" || alltrue([for k in ["desiredState", "eventhubs"] : contains(keys(each.value.parameters), k)])) &&
        (!contains(["microsoft-managedredis-flushdatabase/1.0", "microsoft-managedredis-forceunlink/1.0"], each.value.action_id) || contains(keys(each.value.parameters), "DatabaseName")) &&
        (each.value.action_id != "microsoft-managedredis-forceunlink/1.0" || contains(keys(each.value.parameters), "LinkedDatabaseResourceIds")) &&
      (each.value.action_id != "microsoft-virtualmachinescaleset-shutdown/1.0" || (length(each.value.zones) > 0 && contains(keys(each.value.parameters), "Zones"))))
      error_message = "Required parameters/entity lists must be explicit; VMSS shutdown requires verified region and zone selection."
    }
    precondition {
      condition = (
        (!contains(keys(each.value.parameters), "RestoreOnStop") || contains(["true", "false"], lookup(each.value.parameters, "RestoreOnStop", ""))) &&
        (!contains(keys(each.value.parameters), "SkipIneligibleServers") || lookup(each.value.parameters, "SkipIneligibleServers", "") == "false") &&
        (each.value.action_id != "microsoft-azurepostgresql-failover/1.0" || contains(["PlannedFailover", "ForcedFailover"], lookup(each.value.parameters, "FailoverMode", ""))) &&
        (each.value.action_id != "microsoft-azureclusteredcacheforredis-reboot/1.0" || contains(["AllNodes", "PrimaryNode", "SecondaryNode"], lookup(each.value.parameters, "RebootType", ""))) &&
        (each.value.action_id != "microsoft-eventhub-changeeventhubstate/1.0" || contains(["Active", "Disabled", "SendDisabled"], lookup(each.value.parameters, "desiredState", ""))) &&
        (each.value.action_id != "microsoft-servicebus-changequeuestate/1.0" || contains(["Active", "Disabled", "SendDisabled", "ReceiveDisabled"], lookup(each.value.parameters, "desiredState", ""))) &&
        (!contains(["microsoft-servicebus-changetopicstate/1.0", "microsoft-servicebus-changesubscriptionstate/1.0"], each.value.action_id) || contains(["Active", "Disabled"], lookup(each.value.parameters, "desiredState", "")))
      )
      error_message = "Use the documented case-sensitive Action parameter values."
    }
    precondition {
      condition = alltrue([for key in ["queues", "topics", "subscriptions", "eventhubs", "LinkedDatabaseResourceIds"] :
        !contains(keys(each.value.parameters), key) || (
          can(regex("^\\s*\\[", lookup(each.value.parameters, key, ""))) &&
          try(length(jsondecode(each.value.parameters[key])) > 0 && alltrue([
            for entity in jsondecode(each.value.parameters[key]) :
            startswith(jsonencode(entity), "\"") && can(regex("^[^\\s*]+$", entity))
          ]), false)
        )
      ])
      error_message = "Entity selections must be non-empty JSON arrays of explicit non-blank string names/IDs, without wildcards; verify this encoding with the regional catalog."
    }
    precondition {
      condition = alltrue([for key in ["topic", "DatabaseName"] :
        !contains(keys(each.value.parameters), key) || can(regex("^[^\\s*]+$", each.value.parameters[key]))
      ])
      error_message = "A topic or database parameter must select an explicit non-blank name, never a wildcard."
    }
    precondition {
      condition     = each.value.action_id != "microsoft-virtualmachinescaleset-shutdown/1.0" || try(toset(jsondecode(each.value.parameters["Zones"])) == each.value.zones, false)
      error_message = "VMSS Action Zones must explicitly match the verified configuration zone allowlist."
    }
    precondition {
      condition = each.value.action_id != "microsoft-managedredis-forceunlink/1.0" || try(
        length(jsondecode(each.value.parameters["LinkedDatabaseResourceIds"])) > 0 &&
        alltrue([for id in jsondecode(each.value.parameters["LinkedDatabaseResourceIds"]) :
          contains([for allowed in var.linked_database_allowlist : lower(allowed)], lower(id)) && !contains(local.excluded, lower(id))
        ]), false
      )
      error_message = "Unlink requires an additional explicit allowlist for every affected linked database; discovery scope alone is not authorization."
    }
  }
}

resource "azapi_resource" "configuration" {
  for_each  = var.enabled ? var.scenarios : {}
  type      = "Microsoft.Chaos/workspaces/scenarios/configurations@${local.api_version}"
  name      = "approved-targets"
  parent_id = azapi_resource.scenario[each.key].id
  body = {
    properties = {
      scenarioId = azapi_resource.scenario[each.key].id
      parameters = []
      resourceTargeting = {
        include = merge(
          { resources = sort(tolist(each.value.target_ids)) },
          length(each.value.locations) > 0 ? { locations = sort(tolist(each.value.locations)) } : {},
          length(each.value.zones) > 0 ? { zones = sort(tolist(each.value.zones)) } : {}
        )
        exclude = local.targeting_exclusions
      }
    }
  }
}
