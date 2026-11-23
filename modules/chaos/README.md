# Declarative Chaos Studio configuration

This module uses the published `2026-08-01-preview` [Workspace](https://learn.microsoft.com/en-us/azure/templates/microsoft.chaos/workspaces), [Scenario](https://learn.microsoft.com/en-us/azure/templates/microsoft.chaos/workspaces/scenarios), and [configuration](https://learn.microsoft.com/en-us/azure/templates/microsoft.chaos/workspaces/scenarios/configurations) schemas with AzAPI 2.14.0. Creation is off by default. There are no run actions or scheduling.

Supply exact resource-group scopes and per-Scenario target IDs. One service-direct or qualified VM pressure Action is configured per Scenario. Destructive definitions need an opt-in; it is not execution authorization. The structural Action duration is required by the ARM schema even for Discrete operations and does not imply a timed outage or automatic undo.

Deploy configuration with Reader discovery access first. Separately validate resolved/excluded resources. Copy exact required management/data permissions from that validation into `permissions`, then review a second saved plan. Do not guess roles or use `fixResourcePermissions`. Role assignments stay on exact target resources. Revalidate before running; identity propagation and region/SKU/Action eligibility are cloud checks.

An empty discovered-resource list can require an explicit, separately invoked Workspace `discover` operation; creating scopes and Reader grants alone is not discovery evidence. This operation is not a fault run. For the current native-first workflow and per-case blockers, see the [canonical catalog](../../docs/chaos-test-and-coverage-plan.md#05-原生能力优先本轮执行与暂缓标注).

The deployed API currently normalizes a configuration's `scenarioId` to its parent Scenario name on GET, despite documenting an ARM ID. Requests retain the documented full ID. Only this redundant reference's representation is ignored for drift; a postcondition accepts only the actual parent ID/name. Target filters, parameters, permissions and all other configuration fields remain managed normally. The same handling applies to pod configurations.

Compute stress agents, AKS extension-managed identities and Workspace connections are not provisioned here. The operator installs the AKS extension; this module can then define pod Actions through explicit installation references. Private-cluster compatibility remains a cloud verification gate. Classic targets/capabilities are not a fallback.

For each run record the hypothesis, actual traffic, baseline/SLO, bounded impact, stop thresholds, data ledger and independent recovery path. Stop is not recovery. Return Passed, Failed, Inconclusive or Blocked with a Chinese explanation. Never publish real resource IDs or execution evidence.

## Service-direct parameter contract

`queues`, `topics`, `subscriptions`, `eventhubs` and `LinkedDatabaseResourceIds` require non-empty JSON arrays of explicit string names/IDs. Use `jsonencode(["approved-entity"])`; malformed JSON, objects, non-string elements, whitespace-only names and wildcards are rejected. Confirm that the selected regional Action schema accepts this encoding before deployment; a mock test is not catalog validation.

Managed Redis destructive definitions also require `DatabaseName`, and unlink requires the linked IDs plus their additional allowlist. `SkipIneligibleServers=true` is rejected: an ineligible/skipped target cannot establish coverage. Runtime management/data permissions remain on service-direct targets only; the AKS installer owns its built-in cluster operator assignment.

## Optional single-VM pressure definitions

The UK South regional Action catalog and installed recommended Scenarios were queried read-only for API `2026-08-01-preview`. Their actual parameter keys are `pressureLevel` and `duration`, not `PressureLevel`. Use the installed Scenario Action IDs `microsoft-compute-cpuPressure/1.0` and `microsoft-compute-physicalMemoryPressure/1.0`; the regional catalog's lowercase names and canonical URNs are not substitutes for the Scenario `actionId`.

CPU pressure accepts integer strings 1-100; physical memory pressure accepts 1-99. Both are Continuous, agent-based Actions. The module deliberately supports only **one individual VM per Scenario**, not VMSS/node selection. It requires explicit `pressureLevel`, rejects other input parameters, and derives the parameter `duration` from `duration_minutes` so it matches the structural Action duration (1-5 whole minutes). Pressure above 50 requires `allow_high_pressure_configuration=true`, which remains false by default.

For initial onboarding, keep `enabled=false`, `scenarios={}` and `agent_verified_target_ids=[]` until qualification and ownership review are complete; never apply an empty Scenario map to an already populated owning state. After independently verifying the exact VM's supported guest, managed identity, public outbound connectivity, required permissions, workload headroom, containment and recovery, a private configuration may contain:

```hcl
agent_verified_target_ids = ["<approved-existing-vm-resource-id>"]
scenarios = {
  vm-cpu-low = {
    action_id        = "microsoft-compute-cpuPressure/1.0"
    description      = "Single approved VM, bounded CPU pressure, configuration only."
    target_ids       = ["<approved-existing-vm-resource-id>"]
    duration_minutes = 1
    parameters       = { pressureLevel = "50" }
  }
}
```

The allowlist records a qualification assertion; Terraform cannot prove the guest is qualified. Never add a VM just to bypass the gate. The existing RocketMQ VM needs explicit assessment of indirect broker/data effects, even though broker business cases are unselected. Management/recovery VMs and OS/broker/ledger volumes remain protected.

[Native agent-based Scenarios](https://learn.microsoft.com/en-us/azure/chaos-studio/chaos-studio-scenarios#agent-based-scenario-requirements) install their agent extension automatically when the operator starts the run and leave it installed afterward. Manual classic-agent installation is not a prerequisite. Targets need a managed identity, supported non-Arm OS and public outbound connectivity; private-only networking is not supported. Absence of an inbound public IP alone proves neither outbound access nor incompatibility. Verify these prerequisites without opening private infrastructure, and account for the retained extension in ownership and cleanup planning. `agent_verified_target_ids` asserts this qualification, not that a manually installed agent already exists.

The live catalog lists VM read, extension read/write/delete and Compute location-operation read permissions. These are **not automatically granted** by this feature. Extension lifecycle effects and location-level read scope need separate least-privilege review; copying every permission onto a VM-scoped assignment does not prove the scope is effective. No subscription-wide Contributor, agent installer, Workspace connection, fault run or monitor is added. Revalidate actual targets, permissions and agent readiness before separately authorized execution; static/mock success is not V-03/V-04 acceptance.

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
