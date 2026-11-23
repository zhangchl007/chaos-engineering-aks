# Chaos Studio implementation plan after infrastructure readiness

**Reviewed:** 2026-11-23.
**Current campaign:** Infra-first under the [唯一统一测试用例清单](./chaos-test-and-coverage-plan.md#0-unified-case-standard-and-current-campaign): 70 definitions preserving the original 43 IDs, with all 39 supplied scenarios mapped. Technical phase acceptance does not close business resilience; Cosmos/broker business are unselected and LB/Gateway future. The following engineering-batch history is not a second case catalog or run-authorization source.
**Status:** 用户最新要求助手实际执行 Chaos Studio 原生单 Action 测试并生成报告；按统一清单实时核验、串行执行 eligible PaaS 配置，保留暂不具备能力/安全前置不足的标注。此前配置、availability evidence/stop signal、Blob/Service Bus reference clients 属后续完整 infra/business 验收准备，I2 仍为 partial，不作为当前新增前置。Cosmos DB 本轮不选；下方安装/配置阶段“未执行故障”是历史记录，不覆盖本轮实际执行证据。
**Starting point:** The [deployment runbook](./terraform-deployment-runbook.md) records Workspace and AKS extension installation. These are prior evidence, not fresh live checks; do not rebuild/reinstall them to satisfy historical missing-component statements.

## Current execution priority: native Chaos Studio first

依据用户最新原生测试请求，助手仅执行实时核验合格的已有 PaaS 单故障配置。以[原生能力与暂缓标注](./chaos-test-and-coverage-plan.md#05-原生能力优先本轮执行与暂缓标注)为本轮执行入口；下方历史工程批次/完整业务验收不能成为新增自定义 canary、observer Job、SDK traffic 或 ledger 的前置要求。forced failover、VM/节点中断及破坏性 cache 操作仍分别审查授权/恢复，不自动扩大本轮范围。

**2026-11-23 实际原生执行已完成：** M-01/M-02/P-01/R-01/R-02/B-01/B-02/H-01/H-02 九个 run / Action 均 Succeeded；7项管理面影响/恢复已观察，Redis 两项独立影响证据不足为 Inconclusive。无活动运行，五个 PaaS 目标平台健康 Available，消息实体 Active、数据库 Ready / HA Healthy，Chaos 配置 replan 为0。MySQL 观测断档、PostgreSQL 健康延迟与完整 infra/business 未验证均保留在[测试报告](./chaos-studio-native-test-report.md)；这些实际结果不关闭历史业务工程批次或全部70项验收。

- 已核对现有 Workspace `Succeeded`、25 个推荐 Scenarios；MySQL restart/failover 模板各包含两个 Actions，运行 Configuration 均为 0。只准备/选择单故障，不直接执行组合推荐模板。
- 暂不具备对应原生能力或当前目标/agent/HA/geo 前置不足的用例明确暂缓；不写 guest/proxy 模拟、不自动回退 classic，不为补齐测试修改共享基础设施。
- 停止尚未部署的自定义 K-01 fixture 建设，清理本次不再需要的临时访问；保留已有 Workspace、extension、基础设施和 Terraform ownership。
- 原生 report/资源事件与实际恢复先行；完整 infra/business 验收未执行就标“未验证”。当前没有启动故障，不报告任何用例 Passed。

### Native target binding implementation

| 项目 | 当前实施/验证 |
| --- | --- |
| 资源组与 private AKS | 只使用已批准测试资源组；保持现有 private AKS、private DNS、网络、extension、node pools 不变。没有 Kubernetes Provider 初始化或本地 API 连通要求。 |
| 资源发现根因与修复 | scope/Reader 已存在，但发现快照为空。显式调用官方 `POST Workspace/discover`，0 → 57 个发现资源，无分页；所有六个选中已有目标均在获批资源组。 |
| 原生单故障配置 | 原 Chaos owning state 新增 M-01/M-02/P-01/R-01/R-02/B-01/B-02/H-01/H-02/V-09 共10项；每个 Scenario 仅一个 Action，每个 `approved-targets` Configuration 仅一个明确目标。Queue/hub 使用已有唯一明确实体，不创建业务资源；VM 是私有 RocketMQ VM，排除 jumpserver。自动推荐库不变。 |
| 目标执行权限 | 六个 custom role + 六个 assignment，仅授予 catalog/validation 所需 read、failover/restart/forcereboot、queue/hub write 权限，assignment 在对应实例/namespace；不是订阅 Contributor/Owner。 |
| Saved plan/apply | 两批各审查/apply 同一 private saved plan：共32 create，0已有资源 update/delete/replace；仅20个 Chaos 资源与12个目标授权资源。原 Workspace/runtime/discovery、平台及 Cluster stage 不变。 |
| 原生 validation | **10/10 `Succeeded`**，每项实际解析到唯一指定目标。初次新 RBAC 的失败经真实 role/scope/identity 核对及有限重试后消除；没有扩大权限，不将 HTTP 200 误判成功。 |
| 持久化与 replan | 当前 API GET 将 configuration `scenarioId` 从完整 ARM ID 规范化为父 Scenario 名称。仅对这个冗余引用忽略表示差异，并用 postcondition 校验它确实属于当前 parent；不忽略 targets/参数/RBAC。修复后相同输入 replan detailed exit code **0**。 |
| 废弃自定义准备清理 | 未部署的 K-01 fixture/observer 草稿已删除。guest credentials/tools、临时 VM identity attachment 及七个临时 IAM 资源均已清理；原/并发 VM identities 保留。 |
| 回归与静态检查 | 35个 Chaos module mocks + 4个 stack mocks 通过；stack validate、recursive fmt 与相关 whitespace 检查通过。mock 检查与原生云端 validation 分开，不代表业务或故障验收。 |
| 故障与业务验收 | 没有 Execute、故障启动、业务流量或 SDK Job；原生 configuration/validation 成功不是实际故障或完整业务用例 Passed。 |

执行输入与 state/plan/evidence 保留在受限私有位置，后续必须沿用当前完整输入；不能把初始 `scenarios = {}` 样例重新应用到这个 state。原生能力、当前就绪项与暂缓原因仍以[唯一清单](./chaos-test-and-coverage-plan.md#05-原生能力优先本轮执行与暂缓标注)为准。

### Current blocker corrections and native completion

此前 blanket Blocked 把未配置、未核验、未选择目标和待授权混在一起；当前以[准备状态契约](./chaos-test-and-coverage-plan.md#01-本轮范围与状态)及最新原生清单为准，下方工程批次记录不覆盖当前状态。

| 修复 | 当前证据 / 结果 |
| --- | --- |
| 实际 node 边界 | ARM 实例级核对 User/System 各两节点，均 Running；User 两实例分别在 zone 2、3。新 N-07 只选明确 User VMSS/region/单实例 zone，全部12项配置排除 System VMSS。private AKS 保持不变；不访问本地 private API、不导入或修改 VMSS 生命周期。 |
| 补齐原生配置 | 新增 `n07-single-user-node-shutdown` 与 `p02-postgresql-forced-failover`，均为单 Action、单明确目标；P-02 复用现有服务器权限。扩大 N-01 zone 范围、forced/破坏性运行仍需对应授权。 |
| Scope / IAM / plan | 仅追加 AKS 属性发现的既定 node-group 例外 Reader 与 User VMSS target-only custom role/assignment。Saved plan 为7 create、11 metadata update、0 delete/replace；更新仅 Workspace discovery scope 与原十项配置的 System 排除，不改原 Action/目标/参数/权限。 |
| 原生验证与持久化 | 刷新发现69个资源；当前12项配置绑定7个明确目标资源，**12/12 validation `Succeeded`**。N-07 首次权限求值因新 Reader 尚未传播失败，核对实际 role/principal/scope 后有限重验通过，未扩大权限。相同完整输入 replan exit code **0**。 |
| VM agent 误判 | 原生 pressure 在 Execute 时自动安装并保留 agent，不需先手工安装 classic agent。目标 Ubuntu 22.04 合格，但 VM managed identity 缺失、public outbound/headroom 未核验；V-03/V-04 为 PendingPrerequisite/PendingVerification，不强行修改平台身份/网络。 |
| 准备状态修正 | Pod 目标/私有兼容性为 AwaitingTarget/PendingVerification；N-01 为待配置/范围授权，N-02/N-03 为实例机制待核验；A-02 为数据性质待核验/删除授权，I-01 为机制/目标待确认。未映射等价原生 Actions 继续明确标注，不补自定义模拟。 |
| 真实阻塞保留 | S-03 当前 ZRS 无 geo-failover 前置；A-04 实际数据库无 geo links，无可 unlink 对象。仅该 variant 受影响，不为覆盖率迁移 SKU 或新建 geo 实例。 |
| 故障结论 | 助手未启动故障。Validated 是配置/当前目标解析验证，不是故障、完整 infra 或业务 Passed；单节点仍损失一半 User-pool 容量，用户运行前重查实例匹配、workload 放置、剩余容量与停止恢复。 |

## Infra-first implementation progress

The first bounded infra-first batch adds default-off V-03/V-04 single-VM CPU/memory definitions and synchronizes the manifest registry with all 70 canonical case IDs. The UK South catalog confirms all 16 module Action/resource-type pairs; installed recommended pressure Scenarios confirm the actual `pressureLevel`/`duration` keys and Action ID casing. Raw catalog/qualification evidence stays private.

| Check | Result / scope |
| --- | --- |
| VM pressure safety mocks | 8 passed: default-off creation, synchronized duration, agent target allowlist, pressure bounds/high-pressure opt-in, invalid parameter shapes, and refusal of VMSS/multiple-VM targeting. |
| Existing Chaos service/Pod mocks | 27 passed; existing behavior retained. |
| Chaos stack mocks | 4 passed, including forwarding both pressure safety inputs. |
| Python unit tests | 63 passed. New valid IDs are recognized, undefined IDs rejected, and missing qualification still blocks readiness. Protocol adapters and execution permissions are unchanged. |
| Static configuration | Pinned AzureRM 4.55.0 / AzAPI 2.14.0 module and stack validate; changed HCL formatting, whitespace, exact 70-case registry/catalog consistency and Pylance syntax checks passed. Isolated test copies adapted only their lock constraints; original provider versions/hashes and repository locks are unchanged. |
| TFLint / IaC policy scan | Not executed: tools unavailable in this environment. Existing CI remains the fixed-version scan path; no new scan pass is claimed. |
| Cloud changes / fault acceptance | Historical batch: none. No Terraform apply, HA migration, new identity/permission, agent installation, traffic or fault run in that batch. Current V-03/V-04 preparation is PendingPrerequisite/PendingVerification; native binding changes are recorded above, not superseded by this history. |

This is configuration/runtime-gate preparation, not completion of the infra campaign. Private per-case manifests, independent technical workloads/evidence/monitoring, HA/control prerequisites, unsupported fault mechanisms, actual fault effects and sustained recovery remain outstanding. Cosmos remains unselected and LB/Gateway future; no final successful chaos-test report can yet be issued.

## Initial implementation batch

The configuration-only batch implements strict service-direct entity inputs, five bounded pod Action definitions referencing operator-owned extension installations, and concurrent optional phased HTTPS availability measurements with latency/observation gates. Use the updated [Chaos module contract](../modules/chaos/README.md), [verification contract](../modules/chaos-validation/README.md) and [existing deployment commands](./terraform-deployment-runbook.md).

**Current installation scope is Workspace/Chaos only:** Argo CD and ingress remain disabled. Skip Cluster deployment for Workspace onboarding; the initial Chaos example keeps both Scenario maps empty. Existing Terraform stage/state, provider versions, cache initialization and saved-plan commands are preserved.

This is not completion of the entire runtime plan below. Regional Action schema/permissions, private-cluster functional qualification, real canary/control workloads, protocol-aware hooks, acknowledgment ledgers, independent monitoring/operator handoff, cloud runs and business recovery evidence remain separate gates.

The I2 evidence batch adds opt-in flushed versioned measurements and a separately invoked finite availability stop evaluator. Terraform packages both scripts and forwards the streaming flag, but does not start a monitor or fault. Legacy single-report output and default-off Jobs remain unchanged. See the [live evidence/stop contract](../modules/chaos-validation/README.md#live-evidence-and-independent-stop-signal).

### Latest reference workload batch

The optional [reference clients](../modules/chaos-validation/business.py), [operation ledger](../modules/chaos-validation/ledger.py), and [manifest/recovery gates](../modules/chaos-validation/campaign.py) add bounded Blob S-01 and Service Bus B-01/B-02/B-04 preparation. These are synthetic reference flows, not complete application or fault implementations.

| Latest verified check | Result / scope |
| --- | --- |
| Python unit / offline SDK binding tests | 61 + 2 passed. No service traffic or fault execution. |
| Verification Terraform mocks | 9 passed with Kubernetes 2.38.0 and a reviewed package hash; probe-only/default-disabled Jobs preserved. |
| Root, Bootstrap, Cluster and Chaos validation | All passed; recursive formatting and whitespace checks passed. Bootstrap received only a verified AzAPI package checksum, not a provider upgrade. |
| Optional SDK lock compatibility | Hash-verified Python 3.12 resolution passed; this is not Python 3.12 runtime certification. |
| Dependency advisories | All 17 runtime pins queried against GitHub's pip advisory API; zero matching advisories. The modernization advisory tool does not support Python; no source/image security certification claimed. |
| Current Azure platform preflight | Exact private AKS provisioning Succeeded, power Running, Resource Health Available. No inference about workload readiness. |
| Private access workaround | Isolated non-admin context verified the target, but local private DNS failed. Existing owned VM management-channel probe resolved the endpoint and verified its CA/TLS hostname; HTTP 401 proves transport only. No network change or copied operator credentials. |
| Alternate private gateway | Corrected and reproduced the CLI's mutually exclusive subscription/tenant token arguments. Token acquisition then succeeded, but the official ARM gateway returned HTTP 400 / BadRequest: Run Command is disabled. No cluster setting was changed to bypass that boundary. |
| Approved private access, 2026-11-23 | Temporary managed identity authenticated from the existing VM using SHA256-verified kubectl 1.36.5 and kubelogin 0.2.18 in an isolated directory. Private endpoint and `/readyz` verified; 4/4 nodes and 6/6 Chaos control pods Ready. OIDC, Workload Identity and Azure RBAC enabled. |
| Minimum access and cleanup | Cluster User and RBAC Reader roles plus a custom, registered `nodes/read` data action only; no admin, write or secret access. Reviewed isolated Terraform plans owned only the temporary identity, three assignments and custom read role. All five removed; guest credentials/tools cleaned and original shared-VM identity restored. Platform/Chaos stacks and networking unchanged; Run Command remains disabled. |
| Cloud acceptance | Not run. Current `chaos-targets` has zero workload pods and `chaos-verification` is absent. Real canary/control traffic, durable independent ledger, monitor/stop/recovery qualification and remaining protocol flows are still required. Private access authorization is no longer a blocker; readiness is not business/fault certification. |

Cosmos D-01/D-02 remain optional and unselected by default, not missing mandatory Passed cases. Produce the final successful chaos test report only after actual selected-case fault, impact, containment, data and sustained recovery evidence pass. Do not substitute the 72 local/mock checks or platform availability for that report.

| I2 evidence batch check, 2026-11-23 | Result / scope |
| --- | --- |
| Python tests | 26 passed, including producer/consumer compatibility, live pipe silence without EOF, incomplete/corrupt evidence and early stop thresholds. No real application traffic. |
| Verification Terraform mocks | 9 passed, including script packaging without Jobs and explicit streaming forwarding. Isolated module copy with exact cached Kubernetes 2.38.0; package hash matches the reviewed Cluster lockfile. Repository locks unchanged. |
| Cluster static validation / changed HCL formatting | Passed; no backend migration, Azure plan or deployment. |
| Pylance syntax and producer signature | Passed for changed producer/evaluator and stop tests; resolved producer call sites remain compatible. |
| TFLint / Checkov | Not re-run: executables unavailable in this environment. Historical scanner results below are not new evidence. |
| Cloud baseline, monitor deployment/handoff, fault and business recovery | Not executed; overall I2 and I6 remain incomplete. |

| Initial batch check | Result |
| --- | --- |
| Terraform formatting and root/Cluster/Chaos/module validation | Passed; static configuration checks only. |
| Focused Terraform mock tests | 39 passed: Chaos module 27, Chaos stack 3, verification module 9. |
| Python probe tests and Pylance syntax checks | 9 tests passed; both Python files passed syntax checks. |
| TFLint 0.59.1 on changed Chaos scopes | No errors; two pre-existing library `required_version` warnings remain. |
| Offline Checkov 3.2.495 | Five applicable checks passed, none failed. AzAPI fault semantics/eligibility are not proven by this limited scan. |
| Azure plan/apply, extension installation, traffic, fault and recovery | Not executed; no cloud-readiness or business-resilience claim. |

The table above is the historical configuration batch, not this I2 batch or the subsequent operator installation. Recorded installation confirms version 0.1.12, required components Ready, a dedicated empty target namespace, zero user configurations and no fault/business Job runs. Connection `Pending` is a known preview issue; authenticated fault behavior remains unproven.

Child-module mocks used temporary exact-version validation overrides and cached providers; deployment-stack versions/lockfiles were not changed. Production commands remain the existing readonly initialization and reviewed saved-plan workflow.

## 1. Coverage review

The canonical [chaos testing and Terraform coverage plan](./chaos-test-and-coverage-plan.md) consolidates the former infrastructure review and PaaS draft. It owns case definitions, acceptance, coverage and safety gates; this document tracks implementation batches. Do not repeat infrastructure provisioning or treat historical missing modules, old versions, and download failures as current findings.

| Area | Current source evidence | Remaining work |
| --- | --- | --- |
| Workspace/control plane | [Chaos stack](../stacks/chaos/main.tf) and [module](../modules/chaos/main.tf) declare the recorded installed Workspace/UAMI/discovery grants and optional Scenarios/configurations. No run resource is declared. | Case-specific regional schema, exact discovery/eligibility and effective runtime permissions; preserve recorded ownership. |
| Provider baseline | [Root constraints](../version.tf) and Chaos stack pin AzureRM 4.55.0 and AzAPI 2.14.0. | Revalidate current availability/schema; do not repeat the original 3.115.0/2.7.0 assumptions or upgrade providers as part of onboarding. |
| AKS prerequisites | [AKS module](../modules/aks/main.tf) now configures private access, OIDC, Workload Identity and Azure RBAC for Kubernetes. | Check actual cluster version, architecture, networking, feature state and preview eligibility. Code is not deployment evidence. |
| AKS pod integration | [Pod definitions](../modules/chaos/pods.tf) implement five typed bounded Actions referencing the operator-owned installation. | Private-cluster/image/admission/network qualification and actual approved target/impact evidence; do not duplicate installer resources. |
| PaaS/VM configuration | Service-direct catalog includes MySQL, PostgreSQL, both Redis resource models, Event Hubs, Service Bus, Storage, Cosmos and VM/VMSS Actions. | Choose eligible existing targets and exact entity lists. Harden Action-specific input contracts and validate runtime permissions before use. |
| Business verification | [Probe](../modules/chaos-validation/probe.py) measures concurrent phased HTTPS availability, latency and observation gates; optional live records feed [stop evaluation](../modules/chaos-validation/stop.py). | Real business/protocol flows, durable ledgers, independent deployed monitoring/notification, service/integrity observers and sustained recovery proof. |
| Safety tests | Focused Chaos/pod/measurement tests exist, including strict entity input and independent availability-stop behavior. | New checks validate only their declared scope; mocks/unit tests do not prove Azure support, traffic impact or business recovery. |

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

### Task completion status

| Task | Current status | Unmet exit evidence |
| --- | --- | --- |
| I0 | Partial / privately unverified | Selected-case manifest, actual flow, numeric acceptance, cost/window and recovery approvals. |
| I1 | Workspace baseline installed per runbook | Case-specific discovery, eligibility and permissions. |
| I2 | Availability/evidence/stop and initial Blob/Service Bus reference/ledger/manifest/window code implemented; overall task partial | Actual application and remaining protocol flows, qualified durable independent storage, monitor deployment/freshness/notification, no-fault cloud baseline and recovery rehearsal. |
| I3 | Installation complete per runbook | Private-cluster functional qualification remains separate from installation. |
| I4 | Strict configuration validation implemented; overall task partial | Regional encoding/eligibility, usable permissions and exact cloud resolved-target validation. |
| I5 | Typed pod definitions implemented | Approved configuration and actual functional/containment qualification. |
| I6 | Cloud testing conditionally authorized; not executed in recorded evidence | Current readiness, exact selected scope/contract, actual impact, reconciliation and sustained recovery. Irreversible/expanded branches remain separately scoped. |
| I7 | Deferred | Successful relevant I6 cases and expanded-case approvals. |

### Specific code changes proposed

- Reuse [Chaos module](../modules/chaos/) and [Chaos stack](../stacks/chaos/); do not build a second orchestration framework.
- I4 now rejects malformed/non-list/non-string/blank/wildcard entity input and validates required database/entity/enum parameters. Confirm each selected regional Action's actual encoding and rights; mock tests cannot establish it.
- Keep structural ARM `duration` distinct from effect duration. The current module README notes that the ARM structure requires it even for Discrete Actions; it does not make a restart cancelable or promise a timed outage.
- I5 now uses a separate typed extension path with version `1.0.0`, exact AKS `externalResource` binding and namespace/label/exposure guards. Preserve it independently of service-direct and classic contracts.
- Validate pod namespace membership in the installation allowlist, non-empty restrictive labels, excluded namespaces, selected container where applicable, duration/intensity and eligible node architecture. Preview selected pods before each run, since workload membership is dynamic.
- For pod delete, set graceful deletion and explicit percentage/interval. Do not copy the documentation's 100% example. Percentage rounding and repeated deletion may affect multiple matching pods; use a dedicated recoverable canary and prove the actual maximum affected set before authorizing.
- Keep Action duration at least `PT1M` and at least `durationSeconds`; initially cap effect exposure at 60 seconds, subject to verified schema. CPU/memory require shell/utilities in the target image; network loss must not inherit its documented 100% default.
- I2 now implements concurrent phased availability, latency/observation gates, optional live evidence and a read-only independent stop signal. Retry/backlog/integrity observers, operation-ID reconciliation and cloud handoff qualification remain work; sample windows are not sustained time-window recovery proof.
- Use finite per-phase Jobs or explicitly reviewed deadlines. The existing 900-second Job cannot contain a 15-minute baseline, fault exposure and ten-minute recovery observation. Preserve finite timeouts and cleanup; export evidence before TTL deletion.
- Add only the protocol clients required by the selected first cases, using fixed validated tool images/ConfigMap scripts and least-privilege workload identities. Direct SDK tests must be labeled client-library resilience, not real application resilience.
- Keep fault execution outside Terraform/CI deployment. Separate configuration validation and polling from run start/cancel/recovery; never invoke automatic permission repair or hide API errors.

## 4. Recommended execution waves

Use the case IDs and detailed hypotheses in the [canonical test and coverage plan](./chaos-test-and-coverage-plan.md). Its complete case matrix and dependency gates govern this abbreviated batch ordering, not automatic provisioning.

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

The [canonical acceptance targets](./chaos-test-and-coverage-plan.md#3-workload-and-measurement-design) are proposals, not approved SLAs. Confirm the actual application contract before a run:

- Baseline: 15 minutes and at least 1,000 relevant operations; proposed >=99.9% success within agreed latency SLO. Extend low-volume windows.
- First simulation: 60 seconds, one canary/dependency; Discrete operations have measured, not assumed, outage duration.
- Dependency hard outage: explicit bounded failure or durable queuing under the agreed contract; never false success. Control flow remains within its baseline SLO.
- Short simulation recovery: proposed SLO recovery within 120 seconds after removal, sustained for ten minutes. Record incident RTO separately from removal-to-recovery time.
- Integrity: every acknowledged durable operation reconciled; unknown outcomes resolved; no duplicate committed business effects. Cache-only data is not a durability guarantee.

Before every run, validate the saved targeting policy and compare resolved/excluded resources with the private manifest. Current CLI configuration create/update commands use an older model that does not support `resourceTargeting`; use the verified pinned API path for validation and avoid CLI updates that replace or drop targeting fields.

Stop/escalate on unexpected targets, control-canary SLO breach, integrity loss, loss of recovery access, retry/backlog/capacity budget breach, or approved window expiry. Assign an independent recovery operator. A noncancelable operation cannot be undone by canceling a run.

For network tests, confirm real connectivity after completion: an effect may remain after container restart even when Chaos reports `Succeeded`. Replacement of affected test pods/workloads must be explicitly included in the recovery authorization. Never use Terraform destroy as recovery.

Each case needs: hypothesis/authorization, baseline, selected targets, observed impact/timing, Chaos report, Kubernetes/service evidence, application metrics, ledger reconciliation, stop/recovery actions, sustained post-fault SLO and drift review. Keep actual IDs, request/run IDs, endpoints and raw artifacts private.

Run verdicts follow the existing repository convention: `Passed`, `Failed`, `Inconclusive`, or `Blocked`, with a Chinese explanation. Ordinary missing configuration, prerequisites, verification or authorization use the canonical preparation statuses with `execution=NotRun`, not an automatic campaign-wide Blocked. Evidenced target incompatibility and reproduced unresolved preflight rejection remain explicit. Missing impact/evidence is not a pass; provisioning success is not business resilience.

## 6. First deliverable and deferred scope

**Recommended first deliverable:** Reuse/configure one Workspace, prepare an independent baseline/ledger harness and target namespace, complete operator-led extension checks if pod testing is selected, and define one bounded first-case Scenario. Deploy/run it only through separate approvals.

Do not bundle platform rebuilding, backend migration, provider upgrades, classic fallback, cluster-wide policy relaxation, multi-region fixtures, full-zone loss, cache flush/unlink or automatic fault scheduling.

**Review evidence:** The I2 batch inspected current source and ran the local checks above. Official references below are carried forward from the earlier review. Initial implementation/installation results are historical, not re-certified cloud checks. No Azure inventory, deployment, fault run or business tests were executed by this batch.

## 7. Official references checked on 2026-11-22

- [Workspace Action catalog and semantics](https://learn.microsoft.com/en-us/azure/chaos-studio/chaos-studio-workspaces-supported-resources)
- [AKS extension preview requirements, validated configurations and known issues](https://learn.microsoft.com/en-us/azure/chaos-studio/chaos-studio-aks-extension-overview)
- [AKS installation ownership, namespaces, external resource binding and fault parameters](https://learn.microsoft.com/en-us/azure/chaos-studio/chaos-studio-aks-extension-install)
- [Resource targeting and configuration validation](https://learn.microsoft.com/en-us/azure/chaos-studio/chaos-studio-workspaces-resource-targeting)
