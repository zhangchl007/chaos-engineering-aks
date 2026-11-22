# Chaos Studio implementation plan after infrastructure readiness

**Reviewed:** 2026-11-22.  
**Status:** Initial configuration batch implemented; cloud qualification/deployment/runtime work remains pending. No traffic or fault execution authorized.  
**Starting point:** The operator reports the infrastructure is ready and will install Chaos Studio. This review inspected current source and official documentation, not deployed resources, state contents, or cloud readiness.

## Initial implementation batch

The configuration-only batch implements strict service-direct entity inputs, five bounded pod Action definitions referencing operator-owned extension installations, and concurrent optional phased HTTPS availability measurements with latency/observation gates. Use the updated [Chaos module contract](../modules/chaos/README.md), [verification contract](../modules/chaos-validation/README.md) and [existing deployment commands](./terraform-deployment-runbook.md).

**Current installation scope is Workspace/Chaos only:** Argo CD and ingress remain disabled. Skip Cluster deployment for Workspace onboarding; the initial Chaos example keeps both Scenario maps empty. Existing Terraform stage/state, provider versions, cache initialization and saved-plan commands are preserved.

This is not completion of the entire runtime plan below. Regional Action schema/permissions, private-cluster qualification, operator extension installation, real canary/control workloads, protocol-aware hooks, acknowledgment ledgers, independent stop evaluation, cloud runs and business recovery evidence remain separate gates. The coverage table below records the source-review baseline before this batch.

| Initial batch check | Result |
| --- | --- |
| Terraform formatting and root/Cluster/Chaos/module validation | Passed; static configuration checks only. |
| Focused Terraform mock tests | 39 passed: Chaos module 27, Chaos stack 3, verification module 9. |
| Python probe tests and Pylance syntax checks | 9 tests passed; both Python files passed syntax checks. |
| TFLint 0.59.1 on changed Chaos scopes | No errors; two pre-existing library `required_version` warnings remain. |
| Offline Checkov 3.2.495 | Five applicable checks passed, none failed. AzAPI fault semantics/eligibility are not proven by this limited scan. |
| Azure plan/apply, extension installation, traffic, fault and recovery | Not executed; no cloud-readiness or business-resilience claim. |

Child-module mocks used temporary exact-version validation overrides and cached providers; deployment-stack versions/lockfiles were not changed. Production commands remain the existing readonly initialization and reviewed saved-plan workflow.

## 1. Coverage review

The [coverage plan](./terraform-chaos-coverage-plan.md) has useful safety boundaries and case definitions, but mixes the original infrastructure review with later implementation. Do not repeat infrastructure provisioning or treat historical missing modules, old versions, and download failures as current findings.

| Area | Current source evidence | Remaining work |
| --- | --- | --- |
| Workspace/control plane | [Chaos stack](../stacks/chaos/main.tf) and [module](../modules/chaos/main.tf) declare a Workspace, one UAMI, RG-scoped Reader discovery, Scenarios/configurations and target-scoped custom permissions. No run resource is declared. | Validate the pinned API/provider combination, review exact discovered targets, and establish installation/resource ownership. |
| Provider baseline | [Root constraints](../version.tf) and Chaos stack pin AzureRM 4.55.0 and AzAPI 2.14.0. | Revalidate current availability/schema; do not repeat the original 3.115.0/2.7.0 assumptions or upgrade providers as part of onboarding. |
| AKS prerequisites | [AKS module](../modules/aks/main.tf) now configures private access, OIDC, Workload Identity and Azure RBAC for Kubernetes. | Check actual cluster version, architecture, networking, feature state and preview eligibility. Code is not deployment evidence. |
| AKS pod integration | The Chaos module deliberately excludes extension Actions and has no extension/connection lifecycle resources. | Operator installation plus a separately verified pod Scenario path; merely adding a pod Action ID to the service-direct catalog is insufficient. |
| PaaS/VM configuration | Service-direct catalog includes MySQL, PostgreSQL, both Redis resource models, Event Hubs, Service Bus, Storage, Cosmos and VM/VMSS Actions. | Choose eligible existing targets and exact entity lists. Harden Action-specific input contracts and validate runtime permissions before use. |
| Business verification | [Verification module](../modules/chaos-validation/main.tf) prepares a restricted namespace, ConfigMap and opt-in finite Jobs. [Probe](../modules/chaos-validation/probe.py) measures control then canary sequentially and gates success rate only. | Continuous concurrent measurement, latency/deadline gates, protocol-aware flows, acknowledgment ledgers and recovery evidence. Current probes cannot prove fault-window resilience. |
| Safety tests | [Chaos tests](../modules/chaos/tests/safety.tftest.hcl) cover disabled creation, empty targets, subscription scopes, wildcard permissions, wrong resource type, exclusions and an empty entity list. | Focused malformed-entity, Action contract, pod targeting, containment and measurement tests. Mocks do not prove Azure support. |

**Conclusion:** Infrastructure coverage is the accepted starting point. Declarative service-direct coverage exists but is not verified here; pod integration and end-to-end business resilience remain incomplete. Installation alone does not close either gap.

## 2. Installation decisions to settle first

Chaos Studio is an Azure managed service, not a general Helm installation. Creating a Workspace and installing the AKS extension are separate operations.

### Resource ownership

Recommended split for the operator-led installation:

- Terraform Chaos state owns the Workspace, its runtime identity, discovery grants, service-direct Scenarios/configurations and explicitly reviewed target permissions.
- The operator installs the AKS extension using the documented Azure CLI workflow. That installation owns the extension, subscriber identity/federation, cluster-scoped **Chaos Kubernetes Extension Operator** assignment, and Workspace connection.
- Terraform references installation-owned resources; it must not recreate their role assignment, identity, connection or Helm resources. Declarative adoption is deferred until installation parity and a reviewed import/ownership transition are established.
- If the operator creates the Workspace through the portal instead, do not enable the current creating module against that same object. First choose either approved Terraform adoption or an explicit existing-Workspace input path. Existing-Workspace mode is not implemented today.
- Keep platform, cluster and Chaos state separate. Reuse the existing approved backend mapping; do not change backends or reapply the platform to install Chaos.

### AKS installation checklist

Before installation, choose and create a dedicated fault-target workload namespace. Configure `experiments.targetNamespaces` explicitly; do not accept the default `default` namespace or list system/control namespaces. The installation guide currently requires removal/reinstallation to change this list.

Keep three boundaries separate:

1. Extension control components in `chaos-infrastructure`.
2. Dedicated recoverable target canaries in a reviewed fault-target namespace.
3. Unaffected control canary, verification Jobs, ledgers and recovery access outside the target selection.

The existing verification namespace enforces Pod Security Admission `restricted`. Official documentation says pod-delete helper pods are rejected in restricted target namespaces. Do not weaken the verification namespace or cluster-wide policy. Review a narrow exception only for the dedicated fault-target namespace if needed; extension installation alone does not authorize it.

Also verify:

- Supported Workspace region/data residency independently of the target region.
- Non-production AKS, schedulable Linux amd64 capacity, OIDC, Workload Identity, Azure RBAC, user authentication and private API/DNS connectivity.
- An approved, pinned `k8s-extension` CLI extension version at least 1.9.5; a verified extension version where supported. Record the installed version without blindly using upgrade/latest.
- Outbound access to the Workspace regional data plane, Microsoft Entra ID and extension images; no public API or inbound access workaround.
- Installation permissions separated from runtime/operator permissions. Installation creates its built-in operator assignment at cluster scope; do not use the module's service-direct custom-permission map to replicate it.
- Deployment Safeguards/network daemon requirements before selecting network faults. Any exception is limited to extension infrastructure and explicitly reviewed.

**Private-cluster caveat:** Microsoft currently lists private clusters as unvalidated, not universally unsupported. Do not change this cluster's private boundary or upgrade it automatically. Record an isolated non-production compatibility check as a gate for pod tests. Service-direct and client-path branches can proceed independently when their own prerequisites are satisfied.

Provisioning success and healthy extension pods are installation evidence. The documented connection `Pending` issue is not by itself failure or readiness proof. A separately authorized short fault with observed impact is required to prove functional integration.

## 3. Dependency-ordered implementation

Each work item is bounded; implementation approval is separate from deployment and execution approval.

| ID | Prerequisites | Deliverable | Exit evidence |
| --- | --- | --- | --- |
| I0: Freeze scope and ownership | None | Private target manifest: selected cases, exact IDs/entities, regions/SKUs, state owner, exclusions, operator, cost ceiling, approved recovery and proposed SLO/RTO/RPO. Confirm Workspace creation/adoption choice. | No duplicate ownership; platform is reference-only; unresolved eligibility is recorded per case. |
| I1: Validate Workspace configuration | I0 | Validate the existing Chaos stack with locked providers/API. Prepare Workspace-only configuration and discovery scope; verify an existing-Workspace path only if required. | Static checks pass; reviewed private plan affects only owned Chaos resources; post-deployment discovery is consistent with the manifest. |
| I2: Build measurement and recovery | I0 | Extend the existing harness with phased concurrent control/canary sampling, business flows, identities, private evidence/ledgers, thresholds and independently accessible recovery. Prepare the target namespace/canary separately. | Authorized no-fault baseline proves traffic, business invariants, capacity and recovery access; no general fault-start permissions on Jobs. |
| I3: Install/verify AKS extension | I1, target namespace from I2 | Operator installs the extension with explicit target namespaces and approved versions; record installation-owned resources and compatibility evidence. | Provisioning and pods healthy, required components present, no duplicate Terraform ownership; private-cluster functional readiness remains pending a separately authorized test. |
| I4: Harden service-direct contracts | I1 | Replace permissive entity parsing with verified per-Action serialization/validation; validate required database/entity/enum parameters, semantics, target filters and exact runtime permissions. | Focused mocks reject malformed/empty/wildcard entities and invalid combinations; cloud configuration validation resolves exactly approved targets. |
| I5: Add pod Scenario definitions | I1, I3 | Extend the Chaos module with a distinct typed pod-Action path referencing the existing installation. Preserve service-direct behavior and default-off creation. | Correct published `externalResource`/Scenario parameter/configuration binding; namespace AND label gates; bounded duration/intensity; focused plan tests. No run resources. |
| I6: Execute first bounded cases | I2 plus applicable I4 or I5 | After separate deployment and run approvals, perform one fault per run with baseline, actual impact, stop/recovery and reconciliation. | A case verdict with complete evidence, actual containment, sustained recovery and private drift review. |
| I7: Expand coverage | Clean recovery of relevant I6 cases | Pod stress/network, DB HA, VM/VMSS and optional destructive/DR cases, each with its own prerequisite checks. | Independently reviewed configuration and run window for each case; no automatic escalation or overlapping faults. |

I1 and I2 can progress in parallel. Service-direct I4 does not depend on I3/I5. Pod compatibility failures must not block unrelated service-direct/client-path work.

### Specific code changes proposed

- Reuse [Chaos module](../modules/chaos/) and [Chaos stack](../stacks/chaos/); do not build a second orchestration framework.
- For I4, `try(..., true)` and acceptance of non-list JSON in current entity checks are not strict serialization validation. Define the chosen Action's actual encoding first, then reject malformed JSON, wrong shapes, blank names and wildcards where lists are required. Do not impose one invented encoding on every Action.
- Keep structural ARM `duration` distinct from effect duration. The current module README notes that the ARM structure requires it even for Discrete Actions; it does not make a restart cancelable or promise a timed outage.
- For I5, use extension Action IDs/version `1.0.0` from the official guide, not classic Chaos Mesh URNs. Bind the exact AKS cluster through `externalResource`; the current service-direct resource-type regex/empty Scenario parameters cannot implement this path.
- Validate pod namespace membership in the installation allowlist, non-empty restrictive labels, excluded namespaces, selected container where applicable, duration/intensity and eligible node architecture. Preview selected pods before each run, since workload membership is dynamic.
- For pod delete, set graceful deletion and explicit percentage/interval. Do not copy the documentation's 100% example. Percentage rounding and repeated deletion may affect multiple matching pods; use a dedicated recoverable canary and prove the actual maximum affected set before authorizing.
- Keep Action duration at least `PT1M` and at least `durationSeconds`; initially cap effect exposure at 60 seconds, subject to verified schema. CPU/memory require shell/utilities in the target image; network loss must not inherit its documented 100% default.
- For I2, use concurrent interval-based control/canary observations across baseline, exposure and recovery, not two sequential request batches. Add p95/p99/deadline, retry/backlog and integrity gates, with unknown commit outcomes reconciled by operation ID.
- Use finite per-phase Jobs or explicitly reviewed deadlines. The existing 900-second Job cannot contain a 15-minute baseline, fault exposure and ten-minute recovery observation. Preserve finite timeouts and cleanup; export evidence before TTL deletion.
- Add only the protocol clients required by the selected first cases, using fixed validated tool images/ConfigMap scripts and least-privilege workload identities. Direct SDK tests must be labeled client-library resilience, not real application resilience.
- Keep fault execution outside Terraform/CI deployment. Separate configuration validation and polling from run start/cancel/recovery; never invoke automatic permission repair or hide API errors.

## 4. Recommended execution waves

Use the case IDs and detailed hypotheses in the [PaaS plan](./paas-chaos-test-plan.md). This table orders execution, not automatic provisioning.

| Wave | Cases | Additional gates |
| --- | --- | --- |
| 0: No fault | Connectivity, application/control baseline, identity refresh, ledgers and recovery rehearsal for selected services. | Healthy real traffic and complete evidence; pings alone are insufficient. |
| 1: Minimal impact | C-01/A-01 cache client-path interruption; one dedicated Service Bus queue or Event Hub entity disruption; AKS canary pod delete after compatibility proof. | Choose one first case, not all together. Queue/hub entity selection and prior state must be explicit; validate actual impact and restore state. |
| 2: Recovery behavior | C-02 latency; MySQL M-02 restart; legacy Redis eligible replica reboot; PostgreSQL P-01 planned HA failover; RocketMQ VM restart. | Each has its own data/HA/recovery gate. Cache reboot is `Microsoft.Cache/redis`, never Managed Redis. RocketMQ requires service and message-acknowledgment evidence, not just VM readiness. |
| 3: Pressure/network/nodes | Pod CPU/memory, pod network latency/loss, authorized user-pool VMSS shutdown; forced DB failover only after planned failover recovers. | Preview compatibility and image checks; verified spare capacity/replica placement/autoscaler/storage topology. Exclude system pools and recovery infrastructure. VMSS/zone shutdown may affect every instance in the selected zone; it is not inherently a single-node test or full-zone outage proof. |
| 4: Destructive/DR, opt-in | Managed Redis flush/unlink, Storage planned failover, PITR, geo recovery, eligible Cosmos offline-region. | Separate synthetic data, backup/replication eligibility, impact/cost/window and explicit irreversible-operation approval. Cosmos is optional; do not create it merely to complete a matrix. |

Managed Redis has no direct reboot Action in the current Workspace catalog. Storage account failover is account-wide, not container-scoped. DNS/blackout simulation uses only approved canary hooks or protocol-aware proxies; do not change shared NSGs, DNS or private endpoints.

## 5. Verification and case acceptance

### Development/configuration checks

For the affected stack/modules only, use the existing locked toolchain: formatting, `init -backend=false -lockfile=readonly` when initialization is required, `validate`, focused mock/plan tests, pinned TFLint and the existing IaC policy tool. Review relevant failed policies rather than treating historical scanner counts as a new result or suppressing them globally.

Tests should cover newly added behavior: default-off pod resources, missing external binding, namespace/label escapes, mismatched durations, intensity boundaries, malformed entities, excluded targets, exact RBAC scopes, latency breaches despite successful HTTP responses, concurrent observation and ambiguous acknowledged writes. Add no real apply tests without independent authorization.

For deployment, use the existing correct backend and private inputs to save/review a fresh plan. Stop on platform changes, unexpected RBAC scope, public access, deletes/replacements or duplicate ownership. Apply only the approved saved plan; initialization without a backend is not deployment-ready proof.

### Runtime acceptance proposals

The [PaaS acceptance targets](./paas-chaos-test-plan.md) are proposals, not approved SLAs. Confirm the actual application contract before a run:

- Baseline: 15 minutes and at least 1,000 relevant operations; proposed >=99.9% success within agreed latency SLO. Extend low-volume windows.
- First simulation: 60 seconds, one canary/dependency; Discrete operations have measured, not assumed, outage duration.
- Dependency hard outage: explicit bounded failure or durable queuing under the agreed contract; never false success. Control flow remains within its baseline SLO.
- Short simulation recovery: proposed SLO recovery within 120 seconds after removal, sustained for ten minutes. Record incident RTO separately from removal-to-recovery time.
- Integrity: every acknowledged durable operation reconciled; unknown outcomes resolved; no duplicate committed business effects. Cache-only data is not a durability guarantee.

Before every run, validate the saved targeting policy and compare resolved/excluded resources with the private manifest. Current CLI configuration create/update commands use an older model that does not support `resourceTargeting`; use the verified pinned API path for validation and avoid CLI updates that replace or drop targeting fields.

Stop/escalate on unexpected targets, control-canary SLO breach, integrity loss, loss of recovery access, retry/backlog/capacity budget breach, or approved window expiry. Assign an independent recovery operator. A noncancelable operation cannot be undone by canceling a run.

For network tests, confirm real connectivity after completion: an effect may remain after container restart even when Chaos reports `Succeeded`. Replacement of affected test pods/workloads must be explicitly included in the recovery authorization. Never use Terraform destroy as recovery.

Each case needs: hypothesis/authorization, baseline, selected targets, observed impact/timing, Chaos report, Kubernetes/service evidence, application metrics, ledger reconciliation, stop/recovery actions, sustained post-fault SLO and drift review. Keep actual IDs, request/run IDs, endpoints and raw artifacts private.

Verdicts follow the existing repository convention: `Passed`, `Failed`, `Inconclusive`, or `Blocked`, with a Chinese explanation. Missing impact/evidence is not a pass; provisioning success is not business resilience.

## 6. First deliverable and deferred scope

**Recommended first deliverable:** Reuse/configure one Workspace, prepare an independent baseline/ledger harness and target namespace, complete operator-led extension checks if pod testing is selected, and define one bounded first-case Scenario. Deploy/run it only through separate approvals.

Do not bundle platform rebuilding, backend migration, provider upgrades, classic fallback, cluster-wide policy relaxation, multi-region fixtures, full-zone loss, cache flush/unlink or automatic fault scheduling.

**Review evidence:** Current source and the official pages below were inspected. The initial implementation checks are recorded above; they do not re-certify historical platform checks. No Azure inventory, deployment, fault run or business tests were executed.

## 7. Official references checked on 2026-11-22

- [Workspace Action catalog and semantics](https://learn.microsoft.com/en-us/azure/chaos-studio/chaos-studio-workspaces-supported-resources)
- [AKS extension preview requirements, validated configurations and known issues](https://learn.microsoft.com/en-us/azure/chaos-studio/chaos-studio-aks-extension-overview)
- [AKS installation ownership, namespaces, external resource binding and fault parameters](https://learn.microsoft.com/en-us/azure/chaos-studio/chaos-studio-aks-extension-install)
- [Resource targeting and configuration validation](https://learn.microsoft.com/en-us/azure/chaos-studio/chaos-studio-workspaces-resource-targeting)
