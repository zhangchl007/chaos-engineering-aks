# Declarative Chaos Studio configuration

This module uses the published `2026-08-01-preview` [Workspace](https://learn.microsoft.com/en-us/azure/templates/microsoft.chaos/workspaces), [Scenario](https://learn.microsoft.com/en-us/azure/templates/microsoft.chaos/workspaces/scenarios), and [configuration](https://learn.microsoft.com/en-us/azure/templates/microsoft.chaos/workspaces/scenarios/configurations) schemas with AzAPI 2.14.0. Creation is off by default. There are no run actions or scheduling.

Supply exact resource-group scopes and per-Scenario target IDs. One service-direct Action is configured per Scenario. Destructive definitions need an opt-in; it is not execution authorization. The structural Action duration is required by the ARM schema even for Discrete operations and does not imply a timed outage or automatic undo.

Deploy configuration with Reader discovery access first. Separately validate resolved/excluded resources. Copy exact required management/data permissions from that validation into `permissions`, then review a second saved plan. Do not guess roles or use `fixResourcePermissions`. Role assignments stay on exact target resources. Revalidate before running; identity propagation and region/SKU/Action eligibility are cloud checks.

Compute stress agents, AKS extension-managed identities and Workspace connections are not provisioned here. The operator installs the AKS extension; this module can then define pod Actions through explicit installation references. Private-cluster compatibility remains a cloud verification gate. Classic targets/capabilities are not a fallback.

For each run record the hypothesis, actual traffic, baseline/SLO, bounded impact, stop thresholds, data ledger and independent recovery path. Stop is not recovery. Return Passed, Failed, Inconclusive or Blocked with a Chinese explanation. Never publish real resource IDs or execution evidence.

## Service-direct parameter contract

`queues`, `topics`, `subscriptions`, `eventhubs` and `LinkedDatabaseResourceIds` require non-empty JSON arrays of explicit string names/IDs. Use `jsonencode(["approved-entity"])`; malformed JSON, objects, non-string elements, whitespace-only names and wildcards are rejected. Confirm that the selected regional Action schema accepts this encoding before deployment; a mock test is not catalog validation.

Managed Redis destructive definitions also require `DatabaseName`, and unlink requires the linked IDs plus their additional allowlist. `SkipIneligibleServers=true` is rejected: an ineligible/skipped target cannot establish coverage. Runtime management/data permissions remain on service-direct targets only; the AKS installer owns its built-in cluster operator assignment.

## Optional AKS pod definitions

Leave `aks_extensions={}` and `pod_scenarios={}` for Workspace-only onboarding. No Argo CD or ingress is required. After the operator has installed the extension with the exact target namespaces and recorded approved compatibility evidence, supply references in a private tfvars file:

```hcl
aks_extensions = {
  canary = {
    cluster_id             = "<approved-existing-aks-resource-id>"
    target_namespaces      = ["chaos-targets"]
    compatibility_verified = true
    network_faults_enabled = false
  }
}
pod_scenarios = {
  checkout-pod-delete = {
    description              = "Replace only the dedicated recoverable checkout canary."
    extension_key            = "canary"
    namespace                = "chaos-targets"
    labels                   = { app = "checkout-canary", chaos-canary = "target" }
    fault                    = "pod_delete"
    duration_seconds         = 60
    pods_affected_percentage = 10
    chaos_interval_seconds   = 61
  }
}
```

Do not set verification flags merely to bypass a gate. Namespace membership must match the operator installation. Never target `default`, `kube-*`, `chaos-infrastructure` or `chaos-validation`. Keep the verification/control namespace restricted; review any helper-pod admission exception only on a separate fault-target namespace.

Supported faults are `pod_delete`, `pod_cpu_hog`, `pod_memory_hog`, `pod_network_latency` and `pod_network_loss`, using the documented extension Action IDs/version 1.0.0 and `externalResource` binding. Definitions cap exposure at 60 seconds and affected percentage at 25, require exact AND-matched labels including `chaos-canary=target`, and force graceful deletion with an interval strictly longer than the exposure. Percentages can round up: preview actual matched pods, capacity and maximum impact before every run.

CPU/memory require `target_container`, `container_tools_verified=true` and explicit `cpu_cores` (1-2) or `memory_megabytes` (1-128). Network Actions require verified `network_faults_enabled=true` and explicit `latency_milliseconds` (1-500) or `packet_loss_percentage` (1-10); they use serial selection and no default 100% loss. These configuration bounds are not proof of image, architecture, capacity or recovery eligibility.

The operator installation owns the extension, subscriber identity/federation, Workspace connection and built-in cluster operator role. This module creates none of them. If the Workspace itself was created outside this state, arrange a reviewed adoption first; do not enable this creating module against a duplicate object. `configuration_ids` combines service-direct and pod configurations with unique case-insensitive names. Deploying any definition does not run it.
