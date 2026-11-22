# Terraform chaos coverage review and implementation plan

> **2026-11-22 follow-up:** Infrastructure is ready according to the operator; this review did not query Azure or re-run the historical checks below. The current source already contains Workspace/Scenario configuration, additional service modules, and a bounded HTTPS verification harness. Statements below marked as the original baseline, and their old provider/test blockers, are historical rather than a current installation checklist. Use the [post-infrastructure implementation plan](./chaos-studio-implementation-plan.md) for the next phase. Infrastructure readiness does not establish fault integration or business resilience coverage.

**Reviewed:** 2026-11-20.  
**Status:** Implementation in progress, with explicit validation blockers; no deployment or fault execution authorized.  
**Scope:** Root Terraform, all ten component modules, environment parameter files, provider constraints/lockfile, repository instructions, README, and the [PaaS testing draft](./paas-chaos-test-plan.md).

## 1. Executive conclusion

The original review below describes the pre-implementation baseline. The current implementation status is:

| Area | Code coverage | Verified evidence / remaining gate |
| --- | --- | --- |
| Platform network, AKS/ACR | Existing modules retained with bounded prerequisite/ownership fixes; actual `spotnodepool` name preserved | VNet 3 mock tests; AKS 2 targeted configuration mocks. Complete root/cluster migration plan remains Blocked. |
| MySQL, PostgreSQL, Cosmos DB | Private fixture modules and optional root wiring | 14 mock tests passed. Application SQL users/identity grants, real access, HA/restore eligibility and data reconciliation remain separate prerequisites. |
| Event Hubs, Service Bus, Storage | Private fixtures, explicit entities, root wiring and shared DNS | 12 mock tests passed, including the corrected Storage ARM RBAC scope. Default ZRS/single-region fixtures do not cover geo failover/recovery. |
| Managed Redis / legacy Redis | Separate modules, private/keyless configuration, disabled/reference/eligibility paths | Blocked: AzAPI 2.14.0 binary could not be restored on this network; their tests were not executed. Existing-resource naming/key-auth changes remain migration-sensitive. |
| VM / RocketMQ | Compatible VM module and explicit private/pinned root profile | VM 3 mocks passed. Reproducible RocketMQ artifacts/bootstrap, readiness and message ledgers are not implemented or proven by those VM tests. |
| AGFC, ingress, ArgoCD | Azure AGFC plus separate controller/GitOps profiles; retired/public profiles opt-in only | Cluster stage readonly initialization/static validation passed; ingress 3 mocks passed. ArgoCD/ALB have no executed mocks. Private AGFC/extension compatibility remains Blocked. |
| Monitoring | Bounded Log Analytics and opt-in category-validated diagnostics | Diagnostic module 2 mocks passed. Application SLO metrics, alert routing and independent stop evaluation still need application/operator inputs. |
| Verification | Restricted namespace, ConfigMap script, finite digest-pinned opt-in Linux Jobs with RuntimeDefault seccomp | 6 Terraform mocks and 4 Python tests passed. HTTP availability only: no protocol-aware hooks, acknowledged-write ledgers or complete business resilience proof. |
| Chaos control plane | Disabled Workspace/identity/scoped RBAC, single-Action Scenarios/configurations, explicit entity/zone/exclusion guards | Root, bootstrap, Chaos stage/module and root wiring tests are Blocked by the missing AzAPI package. No Action was started. |
| Pod extension / compute agents | Coverage and ownership gates documented, not guessed resources | Blocked pending private/support/installation-parity verification; no silent classic fallback. |
| CI / provider supply chain | Fixed validation-only workflow and reviewed Linux lock selections | No Azure credentials/deployment steps. Linux HashiCorp packages were SHA256-verified; AzAPI publisher ZIP checksum is recorded but the binary remains unavailable. Extend platform locks before using other architectures. |

**Executed local evidence:** 45 Terraform mock/targeted-plan tests and 4 Python unit tests passed. All HCL formatting passed. Cluster stage `init -backend=false -lockfile=readonly` and `validate` passed. Workflow YAML and its five Bash steps passed syntax validation. These are not cloud tests.

| Check | Result | Explanation |
| --- | --- | --- |
| Formatting / executed focused tests | Passed | 配置格式和已执行的约束测试通过；不代表部署、故障命中或业务恢复通过。 |
| TFLint 0.59.1 | Passed at error threshold, 69 warnings remain | 无 error，但存在 69 条 warning；兼容性保留的旧输入等警告未被隐藏。 |
| Checkov 3.2.495, offline | Failed: 72 passed checks, 37 failed checks, 0 parsing errors | 策略检查仍失败；需逐项评审适用性或修复，不能为凑绿色结果而重构已工作的模块。 |
| AzAPI-dependent validation | Blocked | 官方包下载超时，官方源码构建也被网络阻塞；未绕过校验或伪造通过结果。 |
| Full saved plan / deployment / fault / business recovery | Blocked / not executed | 没有云端授权、迁移审查和真实流量/数据恢复证据。 |

Policy findings include NSG/network policy, encryption/CMK, geo protection, ACR controls and VM settings. Some reflect deliberate lab/legacy contracts; the MySQL/PostgreSQL private-endpoint checks also need applicability review because delegated private networking is a different supported model. No global suppressions or automatic scope-expanding fixes were added.

**Preservation gate:** structural/provider/interface edits remain provisional, not declared safer merely because individual mocks pass. In particular, do not apply the changed root to an existing state: duplicate old RG ownership could cause deletion without a reviewed migration. See the [deployment and migration runbook](./terraform-deployment-runbook.md).

### Original review baseline

**No: the chaos components are not covered by Terraform.** The active root calls only VNet, AKS, and Redis modules. These provision potential targets, not a chaos testing system.

There are no declared Chaos Studio Workspaces, Scenarios, Scenario configurations, Workspace connections, chaos runtime permissions, AKS chaos extension, compute chaos agent, business validation Jobs, or chaos-specific monitoring/stop automation. No Terraform test files or CI workflows were found. Existing AKS identities/RBAC are for cluster networking and image pulls, not chaos execution.

The PaaS draft describes tests but does not provision them. It also includes products absent from the repository and omits AKS, Cosmos DB, Event Hubs, and VM-specific tests. Treat the two documents as complementary: this document covers infrastructure ownership and implementation; the PaaS draft supplies proposed business flows and recovery criteria.

Coverage means both reproducible **configuration** and independently proven **business recovery**. Terraform must not start faults. Run authorization, traffic generation, fault execution, stop decisions, data reconciliation, and recovery remain separate operational steps.

This is a source review, not a deployed-resource inventory. Commented-out calls may correspond to resources in another state or resources created outside Terraform; their absence from the active root is not proof that no deployed target exists.

## 2. Coverage matrix

### Platform components

| Component | Current coverage | Required implementation or decision |
| --- | --- | --- |
| Target infrastructure | Partial: active VNet/AKS/Redis; other root calls disabled | Resolve ownership and privately inventory approved existing targets before enabling/provisioning anything. |
| Workspace and discovery scope | Missing | Dedicated non-production Workspace, narrowly scoped discovery, explicit runtime identity, Reader access only over the selected discovery scope. |
| Scenarios and configurations | Missing | Verified Actions, parameters, duration semantics, include/exclude policy, and stable scenario keys. Configuration must never invoke a run. |
| Workspace runtime RBAC | Missing | Action-derived permissions on approved resources only; separate deployer, runtime, operator, and application identities. |
| AKS pod fault integration | Missing | Extension, Workspace connection, extension-managed subscriber identity/federation, and installation-created operator assignment; verify ownership before any Terraform adoption. |
| AKS node fault integration | Missing | Discover the node resource group and approved VMSS; constrain node pool/zone and verify actual instances. Do not manage the VMSS lifecycle. |
| VM/VMSS CPU and memory agent | Missing | Only required for selected agent-based compute Actions; verify OS, networking, identity, extension schema, and installation lifecycle first. |
| Client-path simulation | Missing | Dedicated application hooks or protocol-aware proxies for selected cloud AKS canaries; not shared NSG/DNS changes. |
| Workload and validation harness | Missing | Isolated namespace, labeled canary/control, ConfigMaps, pinned images, finite Jobs, workload identities, and acknowledgment ledgers. |
| Observability and stop evaluation | Missing | Reuse approved monitoring or add bounded diagnostic settings/alerts, application metrics, Kubernetes evidence, and an independent recovery path. |
| Recovery fixtures/runbooks | Documented only for PaaS | Per-case recovery, backup/replication checks, temporary fixture ownership, and cleanup limits; do not implement recovery as automatic Terraform actions. |
| State, policy, CI and module tests | Incomplete/missing | Environment/state isolation, protected backend bootstrap, readonly lockfile initialization, fixed-version checks, and focused plan-only/mock tests. |
| Classic targets/capabilities/experiments | Missing, **not required by default** | Workspaces-first. Evaluate classic only through an explicit capability-gap decision; no automatic fallback or mixed resource models. |

### Target services and scenario scope

All rows below currently lack Terraform-managed chaos configuration.

| Target / source | Infrastructure state in the active root | Proposed testing path and prerequisites |
| --- | --- | --- |
| AKS pods: [AKS module](../modules/aks/main.tf) | Active; OIDC on, Workload Identity off, no Azure RBAC for Kubernetes configuration | Extension preview: pod delete, CPU hog, memory hog, network latency, network loss. Require namespace AND labels, Linux amd64 target selection, eligible images, supported networking, and a tested recovery path. |
| AKS nodes: [AKS module](../modules/aks/main.tf) | Active node pools; no explicit zones | Workspace compute/VMSS shutdown, not a pod fault. Discover infrastructure resource group from AKS; limit approved VMSS and actual zone membership. NAP pools are excluded. Zone tests are Blocked until topology/capacity are established. |
| Managed Redis candidate: [Redis module](../modules/redis/main.tf) | Active `Microsoft.Cache/redisEnterprise`; product/SKU eligibility still needs verification | Start with client-path interruption and cache-aside checks (A-01/C-01). Catalog flush/unlink Actions are destructive/topology-changing and opt-in. No direct Managed Redis reboot is listed in the current Workspace catalog. |
| MySQL Flexible Server: [MySQL module](../modules/mysql/main.tf) | Root call commented out | Catalog failover/restart (M-01/M-02), subject to healthy HA, networking, and Action eligibility. PITR (M-03) is a separate native recovery drill. |
| Cosmos DB: [Cosmos module](../modules/cosmosdb/main.tf) | Root call commented out; one geo location configured | Catalog offline-region Action needs an eligible topology and actual resource-type/API match; first design client outage/throttle tests with acknowledged-write reconciliation. Multi-region provisioning is a separately costed decision. |
| Event Hubs: [Event Hubs module](../modules/eventhub/main.tf) | Root call commented out | Catalog entity-state Action with an explicit event hub list. Test producer acknowledgments, partition sequence/checkpoints, duplicate handling, retention, and bounded backlog drain. Event Hubs is not Service Bus. |
| VM / RocketMQ: [VM module](../modules/vm/main.tf) | Root call commented out | Dedicated VM restart/shutdown; CPU/memory only with validated agent prerequisites. For RocketMQ, prove acknowledged message recovery and consumer effects; jump/recovery hosts are excluded from faults. |
| PostgreSQL Flexible Server | No module | P-01/P-02 and PITR P-03 require an approved existing fixture or separately authorized new infrastructure. Not mandatory merely because they appear in the broader PaaS draft. |
| Legacy Azure Cache for Redis | No `Microsoft.Cache/redis` resource | R-01/R-02 reboot applies only to eligible legacy caches, not this repository's `redisEnterprise` target. Prefer approved existing fixtures; do not add a legacy cache by default. |
| Storage | No account/container module | S-01 client tests, S-04 protection recovery; S-02/S-03 require eligible geo-redundancy. Never fault backend, evidence, backup, or recovery storage. |
| Service Bus | No namespace/entity module | B-01/B-02/B-03 need explicit dedicated entities; B-04 requires consumer/outbox behavior. B-05 is native regional recovery, not queue-state chaos. |
| VNet, ingress, Application Gateway for Containers, ArgoCD, ACR | VNet/ACR active; AGFC/ArgoCD calls commented; ingress not called | Supporting/recovery infrastructure by default. Test application paths instead of disrupting shared control components. AGFC is not `Microsoft.Network/loadBalancers`; do not reuse a load-balancer Action based on its module name. |

For C-01 through C-05, R-03, A-01/A-03, S-01/S-02/S-04, B-04/B-05, M-03/P-03, and E-01/E-02, Terraform may prepare fixtures/configuration, but does not perform the operational test. Do not report these cases as covered by a service-direct Chaos Action.

## 3. Code review findings

Priorities indicate implementation order, not an exploitability assessment. Existing issues are recorded here; this planning change does not alter infrastructure.

| ID / priority | Evidence and consequence | Required correction / verification |
| --- | --- | --- |
| F-01 / P0 | [Root](../main.tf#L9) and [AKS module](../modules/aks/main.tf#L12) both declare the same resource group name. Two resource addresses claim one Azure object. The AKS module has no direct reference to the root resource group, so name strings also do not establish creation ordering. | Select one owner, preferably root; child consumes it. Inspect actual state before an approved moved/import migration. Never remove state or recreate the resource group to hide this. |
| F-02 / P0 | [AKS](../modules/aks/main.tf#L27) sets `private_cluster_enabled = false`, contrary to the [README](../README.md). | Confirm intended private boundary; separately review networking/replacement risks and runner DNS/access. Do not keep/open public access just to install chaos tooling. |
| F-03 / P0 | [AKS](../modules/aks/main.tf#L40) disables Workload Identity and lacks Azure RBAC for Kubernetes configuration. [Environment files](../environments/) select Kubernetes versions outside the extension's currently validated 1.35/1.36 set. | Review an explicit AKS prerequisite change. Do not blindly upgrade or claim unsupported versions cannot work; validate on an isolated non-production cluster. Private clusters are currently unvalidated by the extension documentation. |
| F-04 / P0 | [Root](../main.tf#L49) and [AKS](../modules/aks/main.tf#L106) run credential-generating provisioners; AKS requests admin credentials and writes them using `local_file`. Child kubeconfig outputs lack explicit sensitivity. [.gitignore](../.gitignore) does not exclude generated kubeconfigs, plans/plan JSON, or `.env`. | Separate cluster configuration state/stage, use short-lived Entra authentication, stop provisioning admin credential files, mark any retained sensitive outputs, and add explicit ignores. Sensitive flags alone do not remove credentials from state. |
| F-05 / P0 | [Development parameters](../environments/dev-variables.tfvars#L93) contain a non-empty password assignment; [root password input](../variables.tf#L313) lacks `sensitive`. | Treat the assignment as sensitive until privately verified as a placeholder. If a live credential was committed/exposed, rotate it and assess repository history separately; do not reproduce it in reports. Use private input/secret references and mark both input boundaries sensitive. |
| F-06 / P0 | [version.tf](../version.tf#L33) uses one local state path; environment tfvars do not select state. [Provider](../providers.tf#L5) disables protection against deleting a non-empty resource group. | Establish independent backend keys/identities per environment and stage. Bootstrap protected backend storage independently; backup/migration requires separate authorization. Review resource-group deletion safety and persistent-resource protection. |
| F-07 / P1 | [Redis](../modules/redis/main.tf#L74) always indexes database `[0]` for key retrieval; [outputs](../modules/redis/outputs.tf) do the same even when `use_azapi=false` creates zero resources. | Define the switch contract; condition all dependent reads/outputs or explicitly reject unsupported false input. Add a focused test for disabled behavior; do not hide errors with blanket `try`. |
| F-08 / P1 | [Redis](../modules/redis/main.tf#L45) disables AzAPI schema validation for both resources. The environment-normalized local name is unused, so [cluster naming](../modules/redis/main.tf#L32) does not enforce environment separation. No private endpoint/DNS configuration is present. | Validate the pinned API body and enum values, re-enable schema validation where supported, establish safe unique naming without an unreviewed replacement, and verify private service access. AzAPI 2.x object bodies are intentional; do not convert them to strings indiscriminately. |
| F-09 / P1 | [MySQL](../modules/mysql/main.tf#L8) silently falls back to the AKS node subnet when `mysql-subnet` is missing, despite delegated-subnet requirements. HA is always emitted and descriptions list modes inconsistently. | Require a valid dedicated delegated subnet, validate HA/SKU combinations, and omit HA only when the locked schema permits that contract. Verify backups/HA before selecting failover. |
| F-10 / P1 | [Cosmos](../modules/cosmosdb/main.tf#L89) and [Event Hubs](../modules/eventhub/main.tf#L71) create private endpoints without a private DNS zone group/record association. Neither explicitly disables public access. Event Hubs' `enable_private_endpoint` input is ignored. | Complete DNS integration, explicitly preserve the approved private boundary, and implement/test the endpoint toggle plus dependent output. Do not assume a VNet DNS link alone creates endpoint records. |
| F-11 / P1 | [ACR lookup](../modules/aks/acr.tf#L5) treats every failed CLI lookup, including access/network errors, as nonexistence and may choose creation. The existing-registry switch is not wired into that decision. | Use explicit existing/new ownership inputs and provider-specific lookup; surface lookup failures rather than silently creating a replacement target. |
| F-12 / P1 | [CLI constraint](../version.tf#L31) allows 0.14, but [root](../variables.tf#L398) and [VM module](../modules/vm/variables.tf#L33) use optional object attributes with defaults, requiring Terraform 1.3+. Several root variables lack types/descriptions; no input validations were found. | Select/pin a tested CLI, raise the accurate minimum, and declare required provider sources for participating modules. Mock tests require an appropriate newer baseline. Keep AzureRM upgrades independent, with schema/plan/replacement review. |
| F-13 / P1 | [Ingress](../modules/ingress/main.tf#L3) references undeclared `random_pet.rg`; [AGFC integration](../modules/agfc/kubernetes-integration.tf) defines namespace/RBAC but no controller installation. Neither is active in root. | Do not enable dormant modules as if complete. Fix and validate each selected module independently, including controller identity/chart integration, before making it a test dependency. |
| F-14 / P2 | [VM defaults](../modules/vm/variables.tf#L38) use mutable image versions and public IPs; [ArgoCD](../modules/argocd/main.tf#L25) enables insecure/plaintext settings. [README](../README.md) references an absent bootstrap script, overwrites provider definitions, and does not match the actual backend/provider configuration. | Correct only components chosen as dependencies in separate bounded changes; pin validated images, preserve TLS/private access, and replace stale operational instructions before they are used. |

The `redisEnterprise` resource type alone does not distinguish every eligible Redis product/SKU. Likewise, names such as `spotnodepool` do not establish Spot configuration: its Spot settings are commented out. Use actual properties and observed placement, not names, to design faults.

## 4. Resource model and provider decision gate

Use [Workspaces](https://learn.microsoft.com/en-us/azure/chaos-studio/chaos-studio-workspaces-overview) for new configuration. The [Action catalog](https://learn.microsoft.com/en-us/azure/chaos-studio/chaos-studio-workspaces-supported-resources) confirms service-level paths described above, but is not evidence that a locked Terraform provider implements them.

Before writing Chaos HCL:

1. Privately inventory resource IDs/types, tenant/subscription, regions/SKUs, HA, private connectivity, state ownership, approved namespace/entity lists, and cost ceilings. Determine which broader PaaS products are actually in scope.
2. Inspect installed provider schemas and version-specific documentation. AzureRM is pinned to `3.115.0`; the active Redis module constrains AzAPI to `2.7.x`, with `2.7.0` in the lockfile. Workspace/connection/Scenario/configuration support in these versions is **unverified**, not assumed supported or definitively unsupported.
3. Verify published ARM resource schemas/API versions for Workspace, Scenario, configuration, connection, extension, and identity lifecycle. Use AzureRM where the selected version supports the resource; otherwise evaluate pinned AzAPI. Never have both manage the same object.
4. Retrieve the selected Workspace region's Action schema and eligibility rules. Distinguish Discrete, Continuous, and Cancelable. Do not transplant classic fault URNs or assume one duration format covers everything.
5. [Resource targeting](https://learn.microsoft.com/en-us/azure/chaos-studio/chaos-studio-workspaces-resource-targeting) is documented in `2026-08-01-preview`; `resourceTargeting` replaces earlier `filters`/`exclusions`. Verify the complete chosen schema; do not mix the generations or assume the current CLI configuration commands support the newer model.
6. Validate extension installation parity. [Installation documentation](https://learn.microsoft.com/en-us/azure/chaos-studio/chaos-studio-aks-extension-install) uses a CLI workflow that also creates a Workspace connection and operator assignment, while AKS creates subscriber identity/federation. A generic cluster-extension Terraform resource is not proven equivalent. If declarative support cannot reproduce the lifecycle, mark pod integration Blocked and document a separately approved installation/adoption approach; do not disguise it as Terraform coverage.

For pod integration use one system-assigned Workspace identity OR exactly one user-assigned identity, following the extension prerequisites. Do not duplicate the installation-owned **Chaos Kubernetes Extension Operator** assignment or subscriber identity. Classic Chaos Mesh is a different path, not a universal dependency.

## 5. Proposed Terraform and ownership design

Preserve root orchestration, [modules](../modules/), and non-sensitive [environment parameters](../environments/). Add only components selected through the decision gate:

| Proposed location | Responsibility |
| --- | --- |
| `modules/chaos/main.tf`, `variables.tf`, `outputs.tf`, `README.md` | Verified Workspace/Scenario/configuration resources and inputs/outputs. Split identity/RBAC/Scenario files only when useful. No shared service ownership, provisioners, REST run calls, or scheduling. |
| `modules/chaos-aks/` if extension parity is proven | Only declaratively ownable extension/connection integration. Do not recreate AKS-owned subscriber identity/federation. Explicitly document externally owned resources. |
| `modules/chaos-validation/` in a separate cluster configuration stage | Canary/control namespace, scripts through ConfigMaps, service accounts/federation references, and finite validation Jobs. Deploying a Job executes code, so its deployment also needs explicit authorization; no fault-start permissions in business Jobs. |
| Dedicated environment/stage roots, only where state separation requires them | Infrastructure, chaos configuration, and cluster configuration use distinct backend keys and suitable runner access. Reference narrow module outputs or provider data sources, not entire remote states. |
| Separate fixture modules, only for selected missing products | Non-production PostgreSQL/Storage/Service Bus or approved legacy Redis fixtures. Own their private networking, data protection, and cleanup boundaries separately from the chaos module. |
| CI policy/check configuration | Static and mocked/plan-only checks by default; deploy and run workflows are distinct and require scoped authorization. |

Minimum input contract:

- Creation defaults off (`enable_chaos=false`); this is not permission to run.
- Typed stable-key maps for targets and scenarios; non-empty approved IDs and verified resource types.
- Explicit discovery scopes, target allowlist, exclusions for production/shared/recovery resources, and Action-specific entity/namespace/label constraints. Dynamic discovery must be compared with the authorization list before every run.
- Explicit Workspace identity selection, target-scoped role assignments derived from validation, and operator permissions separate from deployment/RBAC administration.
- Duration/intensity limits validated against the selected Action. Reject empty selectors, invalid environments, unsupported combinations, and destructive Actions without the relevant opt-in contract.
- Explicit tags including environment, project, owner, cost center, and managed-by; placeholder values only in committed examples.
- Outputs limited to needed resource IDs and non-secret integration metadata; no access-key retrieval purely to configure chaos.

The module allowlist is a safety contract, not an invented ARM property. Implement it using the verified discovery/targeting schema plus narrow RBAC. If an API cannot express the approved boundary, block that Scenario instead of widening scope.

## 6. Dependency-ordered implementation plan

Each row is a bounded deliverable suitable for its own change. No row authorizes Azure mutation or test execution.

| Task / priority | Depends on | Deliverable and completion criteria |
| --- | --- | --- |
| T0 / P0: Resolve scope/support | None | Private target/state inventory; selected cases, region/SKU/Action/provider/API evidence, cost ceiling, ownership map. Missing evidence remains Blocked. Start with existing approved AKS/Redis targets; broader services are opt-in. |
| T1 / P0: Correct ownership/state | T0 | Resolve F-01/F-06; independently bootstrap protected backend and isolate environments/stages. Approved migration plan shows no accidental deletion/replacement or duplicate ownership. |
| T2 / P0: Correct selected prerequisites | T0 | Resolve F-02 through F-05 and selected F-07 through F-14. Explicit network/identity/credential changes and accurate CLI baseline; validate selected dormant modules without enabling all of them. |
| T3 / P1: Create chaos configuration | T1, T2 | Add Workspaces-first module after provider gate. Default disabled yields no chaos resources/roles; enabled yields only approved configuration. No execution path. |
| T4 / P1: Prepare measurement | T1, T2 | Real application canary/control, ConfigMaps/Jobs, private connectivity, identity, independent ledgers, dashboards/alerts, and bounded cleanup. Existing approved monitoring is reused where possible. |
| T5 / P1: Prepare AKS pod integration | T3, T4 | Only after extension parity/configuration validation: install/adopt supported resources with single ownership. Verify provisioning, namespaces, network component, and recovery procedure; connection `Pending` alone is not a readiness verdict. |
| T6 / P1: Prepare individual service/node cases | T3, T4 | One Action per initial configuration. Redis client interruption first; MySQL/Event Hubs/VM cases only on selected fixtures. Nodes require observed topology, explicit VMSS/zone containment, capacity, and autoscaler evidence; no VMSS imports. |
| T7 / P2: Prepare expanded/destructive/DR cases | T0, T6 | Separately costed fixtures for absent products, Cosmos multi-region if selected, and recovery runbooks. Full cache flush/unlink, region/account-wide failover, and combined faults remain off and separately authorized. |
| T8 / P1: Authorized cloud validation | Applicable T3-T7 tasks | Separate reviewed saved plan and deployment authorization, then separate fault/recovery authorization. Validate actual traffic impact, containment, business SLO, integrity, recovery, and private drift evidence. No automatic promotion to production. |

Add focused tests alongside T2/T3 rather than postponing them to T8. T4 and T3 can progress independently after their shared prerequisites. Pod testing, service-direct testing, and node testing are separate branches; one need not block the others when its own support is missing.

Recommended first release: corrected ownership/private access/identity prerequisites, isolated state, disabled-by-default chaos configuration, and a canary/control harness. Then select one bounded client-path test; enable a short pod-delete case only after extension compatibility is proven. Do not start with full-zone loss or cache flush.

## 7. Verification, authorization, and recovery

### Static and plan-only checks

- Format touched Terraform files; repository-wide formatting cleanup is a separate change.
- Initialize without backend access using `terraform init -backend=false -lockfile=readonly`, then `terraform validate`; pin the chosen CLI in CI.
- Validate participating child modules independently. Root validation does not cover commented-out modules.
- Run pinned TFLint and one suitable IaC policy scanner. Focus on target containment, permissions, public access, sensitive outputs, shared ownership, and automatic fault execution.
- Focused mock/plan-only tests: creation disabled; malformed/empty targets; production exclusions; namespace/label/entity matching; Action duration/intensity boundaries; destructive opt-ins; exact RBAC scopes; externally owned extension dependencies; Redis and endpoint disabled paths.
- Inspect plan output for resource replacements/deletes, network changes, costs, credential exposure, and role scopes. A policy/test must reject fault-run resources/provisioners, not merely count configuration objects.

### Deployment and fault execution are separate gates

1. Confirm backend, state key, subscription/tenant, identity, target ownership, and absence of overlapping runs.
2. Save and review the correct private plan with `-detailed-exitcode`: 0 means no change, 2 means changes, 1 means error. Apply that same plan only after explicit authorization. Do not use default `-auto-approve` or routine `-target`.
3. Verify configuration and RBAC propagation. Terraform ordering is not proof that permissions are usable.
4. Validate the Scenario's resolved/excluded resources against the exact allowlist and refresh validation if inventory or policy changes. No resolved target or an unexpected target is Blocked, not Passed. Never automatically invoke permission-fixing operations.
5. Obtain execution authorization covering hypothesis, target/data impact, duration, stop thresholds, operator, independently accessible recovery, and any irreversible operations. Jobs and operators must not have general fault-start privileges by default.
6. Start traffic and capture baseline before the separately authorized fault. Reuse the PaaS draft's proposed thresholds only after matching actual business SLO/RTO/RPO; measure real replica placement, queue capacity, and acknowledged data.
7. Stop/escalate on containment breach, integrity loss, loss of recovery access, excessive retries/load, control-canary degradation, or exceeded approved budget/window. Do not assume Discrete operations can be undone.
8. Verify removal of effects, true connectivity, readiness, HA/replication, data/message reconciliation, and sustained business SLO. AKS network effects can remain after a successful run; authorize recovery of affected test pods separately.
9. Inspect drift privately after recovery. Do not let Terraform/GitOps fight the intentional fault or use broad permanent `ignore_changes`; do not use destroy as recovery. Clean up only owned temporary fixtures and assignments.

Use `Passed`, `Failed`, `Inconclusive`, or `Blocked`, with a Chinese explanation. A Chaos `Succeeded` is not a business pass; a skipped fault is not resilience proof. Coverage percentage is informational, not a global threshold.

## 8. Evidence from this review

| Check | Result | Evidence / limitation |
| --- | --- | --- |
| Source and coverage review | Completed | Root, component modules, environment keys/selected non-sensitive settings, constraints/lockfile, instructions, README, and PaaS draft inspected. No Azure inventory queried. |
| `terraform fmt -check -recursive -no-color` | Failed | Existing formatting differences in root `main.tf`, `providers.tf`, and MySQL/Redis `main.tf`. No source formatting changes made. |
| `terraform validate -no-color` | Blocked | Reported uninstalled active modules. Isolated `init -backend=false -lockfile=readonly` discovered the three local modules but stalled while downloading AzAPI; it was stopped. Validation did not complete. |
| CLI / locked versions | Observed only | CLI 1.15.6; lockfile AzureRM 3.115.0 and AzAPI 2.7.0. Reading locked versions is not proof of provider availability or Workspace schema support. |
| Provider/ARM implementation parity | Blocked | Version-specific Workspace and extension lifecycle support still needs verification; no speculative HCL generated. |
| Terraform plan/apply, cloud business or chaos tests | Not executed | No deployment/run authorization supplied; no cloud result claimed. |

**Chinese result summary:** Terraform 混沌组件覆盖不完整；当前只定义了部分目标基础设施。格式检查失败，配置验证因初始化未完成而阻塞；未执行云端部署、故障注入或业务恢复验证，不能判定韧性测试通过。

## 9. Official references

Documentation retrieved on 2026-11-20; re-check at implementation time.

- [Terraform style guide](https://developer.hashicorp.com/terraform/language/style)
- [AzureRM 3.115.0 documentation](https://registry.terraform.io/providers/hashicorp/azurerm/3.115.0/docs)
- [AzAPI 2.7.0 documentation](https://registry.terraform.io/providers/Azure/azapi/2.7.0/docs)
- [Chaos Studio Workspaces overview](https://learn.microsoft.com/en-us/azure/chaos-studio/chaos-studio-workspaces-overview)
- [Supported resources and Actions](https://learn.microsoft.com/en-us/azure/chaos-studio/chaos-studio-workspaces-supported-resources)
- [Workspace permissions and identity](https://learn.microsoft.com/en-us/azure/chaos-studio/chaos-studio-workspace-permissions)
- [Resource targeting and validation](https://learn.microsoft.com/en-us/azure/chaos-studio/chaos-studio-workspaces-resource-targeting)
- [Scenario templates and custom Scenarios](https://learn.microsoft.com/en-us/azure/chaos-studio/chaos-studio-scenarios)
- [AKS node resilience testing](https://learn.microsoft.com/en-us/azure/chaos-studio/chaos-studio-aks-guidance)
- [AKS extension overview and known issues](https://learn.microsoft.com/en-us/azure/chaos-studio/chaos-studio-aks-extension-overview)
- [AKS extension installation and owned resources](https://learn.microsoft.com/en-us/azure/chaos-studio/chaos-studio-aks-extension-install)
