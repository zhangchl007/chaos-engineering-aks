# Chaos Studio 实施计划 / Implementation Plan

**复核日期 / Reviewed：** 2026-11-23。

**阅读规则：** 以中文实际实施进度和下一步为主；英文在对应段落或表格列逐项同步。原英文中的额外工程计划完整保留为后续追加，不因本轮未实施而删除。产品名、任务编号、Case ID、API 参数及状态枚举保持原文。
**Reading rule:** Chinese leads actual implementation progress and next steps; English follows in the matching paragraph or table column. Additional engineering plans from the former English text are retained as follow-up scope, not deleted because they are unimplemented. Product names, task IDs, Case IDs, API parameters and status enums remain unchanged.

**职责：** 本文跟踪工程计划、依赖、实施状态与历史批次，不新增测试用例，也不授权部署、流量、故障或破坏性恢复。实际结果以运行报告为准，静态检查、安装、配置验证和完整韧性验收分开。
**Responsibility:** This document tracks engineering plans, dependencies, implementation status and historical batches. It neither creates another case catalog nor authorizes deployment, traffic, faults or destructive recovery. The execution report governs actual results; static checks, installation, configuration validation and full resilience acceptance are separate.

| 权威文档 / Source | 中文职责 | Corresponding English responsibility |
| --- | --- | --- |
| [统一测试清单 / Canonical case catalog](./chaos-test-and-coverage-plan.md) | 全部70个定义、原43编号和39中文场景映射、范围/准备状态/验收。 | All 70 definitions, 43 original IDs and 39 Chinese scenario mappings, scope/preparation/acceptance. |
| [部署与测试手册 / Deployment and test runbook](./terraform-deployment-runbook.md#chaos-test-operations) | 原 state、配置、安装、运行、停止恢复、项目代码与私有证据的操作步骤。 | Procedures for original state, configuration, installation, execution, stopping/restoration, project code and private evidence. |
| [实际原生报告 / Native execution report](./chaos-studio-native-test-report.md) | 两轮已执行结果、观测缺口、收尾、未运行项及当前 private AKS 限制。 | Results of both executed rounds, observation gaps, final checks, unexecuted cases and current private AKS limitations. |

## 导航 / Navigation

- [0. 当前实际进度与下一步 / Actual progress and next steps](#0-current-progress)
- [1. 现有覆盖与资源归属 / Existing coverage and ownership](#1-coverage-review)
- [2. AKS 安装与兼容边界 / AKS installation and compatibility](#2-installation-decisions-to-settle-first)
- [3. I0–I7 依赖与完成状态 / Dependencies and status](#3-dependency-ordered-implementation)
- [4. 后续执行批次 / Follow-up execution waves](#4-recommended-execution-waves)
- [5. 验证与交付要求 / Verification and delivery](#5-verification-and-case-acceptance)
- [6. 原英文计划保留的后续追加 / Retained follow-up plans](#6-first-deliverable-and-deferred-scope)
- [7. 历史工程批次证据 / Historical engineering evidence](#7-historical-batches)
- [8. 官方参考 / Official references](#7-official-references-checked-on-2026-11-22)

<a id="0-current-progress"></a>
## 0. 当前实际进度与下一步 / Actual Progress and Next Steps

### 0.1 实际实施范围 / Actual implementation scope

本轮采用原生优先：沿用已有 Workspace、extension、基础设施和 Terraform ownership，执行实时核验合格的单 Action PaaS 配置。保持 private AKS；不新增 canary、observer Job、SDK 流量、账本、proxy、guest 模拟或 classic Chaos Mesh 作为原生运行前置。完整 `infra` / `business` 工程仍保留，但不阻塞独立合格的原生路径。
This campaign is native-first: reuse the existing Workspace, extension, infrastructure and Terraform ownership, and execute live-qualified single-Action PaaS configurations. Preserve private AKS; do not add canaries, observer Jobs, SDK traffic, ledgers, proxies, guest simulations or classic Chaos Mesh as native prerequisites. Full `infra` / `business` engineering remains planned without blocking independently qualified native paths.

Cosmos DB D-01/D-02、RocketMQ 业务本轮不选，LB/Gateway 为未来范围；VM/节点中断、forced failover、flush/unlink、范围扩大和恢复生命周期另审。推荐模板可能包含多种 Action，只选单故障，不整套执行。
Cosmos DB D-01/D-02 and RocketMQ business cases are unselected; LB/Gateway are future scope. VM/node interruptions, forced failover, flush/unlink, scope expansion and recovery lifecycle require separate review. Recommended templates may contain multiple Actions; select single faults rather than executing whole templates.

### 0.2 最新已完成与未完成 / Latest completed and incomplete work

| 项目 / Item | 中文实际状态与证据边界 | Corresponding English actual status and evidence boundary |
| --- | --- | --- |
| 已有安装 / Existing installation | Workspace 与 AKS extension 已安装；原生运行不依赖 ingress/Argo CD，二者仍关闭。安装历史不是当前 Pod 故障可用证明。 | Workspace and AKS extension are installed; native execution needs neither ingress nor Argo CD, both remain disabled. Historical installation does not qualify current Pod faults. |
| 发现与首批绑定 / Discovery and initial binding | scope/Reader 已有但初次发现0；显式 discover 后57资源。原 Chaos state 新增10个单 Action/单目标 Scenario+Configuration，六个已有资源、queue/hub进一步单实体，jumpserver排除。 | Scope/Reader existed but discovery was initially zero; explicit discover found 57 resources. Original Chaos state added ten single-Action/single-target Scenario+Configuration pairs for six existing resources, further restricting queue/hub entities and excluding jumpserver. |
| 首批权限与plan / Initial IAM and plan | 六个 custom roles+六个 assignments，授 catalog/validation 所需 read、failover/restart/forcereboot、queue/hub write，赋权精确目标。两批各16 create，共32 create：20 Chaos资源+12授权资源，已有资源 update/delete/replace 0。 | Six custom roles+six assignments grant catalog/validation-required read, failover/restart/forcereboot and queue/hub write on exact targets. Two batches of 16 creates total 32: 20 Chaos resources+12 IAM resources, zero existing-resource updates/deletes/replacements. |
| 原生验证与引用修复 / Native validation and reference fix | 初始10/10 Validate Succeeded，实际唯一目标；RBAC传播失败核真实角色/范围/身份后有限重验，无扩权。API把 scenarioId 从ARM ID规范化为parent名，仅忽略该冗余表示差异，postcondition核parent，不忽略targets/参数/RBAC；完整输入replan 0。 | Initial 10/10 Validate Succeeded with unique targets; investigate RBAC propagation against actual roles/scopes/identities, then finitely revalidate without widening rights. API normalizes scenarioId from ARM ID to parent name; ignore only that redundant representation and verify parent via postcondition, not targets/parameters/RBAC. Full-input replan 0. |
| P-02/N-07 补齐 / Additional configurations | 新增forced PostgreSQL与单User-node shutdown；从AKS nodeResourceGroup发现既定节点组例外，追加Reader与User VMSS target-only role/assignment；所有12配置排System VMSS，不import/修改节点生命周期。 | Add forced PostgreSQL and single User-node shutdown; discover the planned node-group exception via AKS nodeResourceGroup, add Reader and User VMSS target-only role/assignment. All 12 configurations exclude System VMSS, with no node lifecycle import/change. |
| 补齐plan/验证 / Additional plan/validation | 7 create、11 metadata update、0 delete/replace；更新仅discovery scope与原十项System排除。发现69资源、12配置/7明确目标，12/12 Validate Succeeded；N-07 Reader传播有限重验后通过，完整输入replan 0。发现数不是授权数。 | Seven creates, 11 metadata updates, zero deletes/replacements; updates only discovery scope and System exclusions on the original ten configurations. Discovery 69 resources, 12 configurations/seven explicit targets, 12/12 Validate Succeeded after finite N-07 Reader propagation revalidation, full-input replan 0. Discovery count is not approval count. |
| 两轮真实PaaS执行 / Two actual PaaS rounds | M-01/M-02/P-01/R-01/R-02/B-01/B-02/H-01/H-02各执行两轮；每轮9/9 run/Action Succeeded、7管理面Passed、Redis两项Inconclusive。合计18运行仅覆盖9不同用例，完整infra/business未验证。 | Execute M-01/M-02/P-01/R-01/R-02/B-01/B-02/H-01/H-02 twice; each round has 9/9 Succeeded runs/Actions, seven management-plane Passed and two Redis Inconclusive. Eighteen runs cover nine distinct cases; full infra/business remains unverified. |
| 项目代码重跑 / Project-code rerun | 首轮10:16:27–10:50:48，重跑11:24:31–11:55:14（2026-11-23，UTC+08:00）；直接用项目runner/observer/summarizer，不修改源码或放宽guards。73 Python tests通过及12配置实时Validate是该次证据，不是本文重验。 | First round 10:16:27–10:50:48, rerun 11:24:31–11:55:14 on 2026-11-23 (UTC+08:00), using project runner/observer/summarizer without source changes or relaxed guards. The 73 passing Python tests and 12 live configuration validations belong to that run, not fresh checks in this edit. |
| 观测缺口 / Observation gaps | MySQL首次查询timeout断档、PostgreSQL首次Unavailable与重跑Degraded后恢复均保留；同一run恢复观察，不重复Execute。Redis缺独立节点/连接/副本重加入证据，约8–10秒run不是outage/RTO。 | Preserve first-round MySQL query-timeout gap, PostgreSQL first-round Unavailable and rerun Degraded followed by recovery; resume the same run without repeated Execute. Redis lacks independent node/connectivity/replica-rejoin evidence; approximately 8–10-second runs are not outage/RTO. |
| 收尾与持久化 / Final checks and persistence | 五PaaS Available、DB Ready/HA Healthy、queue/hub Active、无活动run、private AKS不变；原Chaos完整输入replan 0、未apply，仅证明Chaos配置无漂移。新cohort不覆盖旧journals/hash。 | All five PaaS Available, DB Ready/HA Healthy, queue/hub Active, no active runs and unchanged private AKS; original Chaos full-input replan 0 without apply proves only Chaos-configuration consistency. New cohort preserves old journals/hashes. |
| 自定义准备清理 / Retired custom preparation | 停止未部署K-01 fixture/observer草稿，guest credentials/tools、临时VM身份attachment和七临时IAM已清；保留原/并发VM身份、Workspace/extension/平台。 | Retire undeployed K-01 fixture/observer drafts, clean guest credentials/tools, temporary VM identity attachment and seven temporary IAM assets; preserve original/concurrent VM identities, Workspace/extension/platform. |

运行、Validate、恢复观察、离线汇总的项目入口与私有cohort操作见 runbook §8.1–§8.8；不得把初始 `scenarios = {}` 重新应用到已有Chaos state。恢复观察指定原cohort/原run，不重放Execute；已有journal会拒绝新执行。本文不复制操作命令或重新授权重跑。
Project entry points and private cohort procedures for execution, Validate, resumed observation and offline summaries are in runbook §8.1–§8.8. Never reapply initial `scenarios = {}` to populated Chaos state. Resume the original cohort/run, not Execute; existing journals refuse new execution. This plan neither duplicates commands nor reauthorizes reruns.

### 0.3 当前未运行原因与下一步 / Current unexecuted work and next steps

| 分支 / Branch | 中文现状与下一步 | Corresponding English status and next action |
| --- | --- | --- |
| Redis 已执行项 / Executed Redis | 保留R-01/R-02原生成功、影响Inconclusive；优先补既有节点/副本事件、实际连通/复制恢复证据，不靠再次成功run冒充命中。 | Retain R-01/R-02 native success and Inconclusive impact; prioritize existing node/replica events and actual connectivity/replication recovery, not another successful run as impact proof. |
| private AKS | 当前ARM/MCP确认private/Available；User/System各两实例在zone2/3，N-07 zone2匹配一个User实例、Validate成功，但关一节点损失半User容量。当前private DNS及精确private endpoint TCP路径不可达，近10分钟inventory查询0行不证明无workload/有容量。N-07/K-01–K-05仍NotRun/PendingVerification。 | ARM/MCP confirms private/Available; User/System each have two instances in zones2/3, N-07 zone2 matches one User instance and Validate passed, but one shutdown removes half User capacity. Current private DNS and exact private-endpoint TCP access fail; ten-minute inventory queries returning zero do not prove no workload/spare capacity. N-07/K-01–K-05 remain NotRun/PendingVerification. |
| AKS 下一步 / AKS next step | 已有获批私网认证执行端核当前Ready/压力、Pod/control/recovery节点放置、副本/存储/剩余容量及匹配；满足授权后先已有N-07单节点，Pod另核extension/namespace AND labels/preview。不开放private API、不启AKS Run Command、不改共享网络、不复制个人token、不默认新身份/权限。 | An existing approved authenticated private host must check current Ready/pressure, Pod/control/recovery placement, replicas/storage/spare capacity and matching. Once qualified/approved, start with existing single-node N-07; separately qualify Pod extension/namespace AND labels/preview. No public private-API exposure, AKS Run Command, shared-network changes, copied personal tokens or default new identities/rights. |
| VM pressure | V-03/V-04定义默认关闭、单VM、初始≤50%；原生Execute自动安装并保留agent，不需classic预装。Ubuntu22.04合格，但VM managed identity缺失、public outbound/headroom/恢复待核验；原owning state补前置需相应授权，不强改平台。 | V-03/V-04 definitions default off, single VM, initial ≤50%; native Execute installs/retains agent, no classic preinstallation. Ubuntu22.04 qualifies but VM managed identity is missing and public outbound/headroom/recovery unverified; prerequisite changes in original owning state need relevant approval, not forced platform edits. |
| 扩大/破坏性 / Expanded/destructive | P-02配置Validated仍AwaitingAuthorization；V-09先核broker/间接消费者与guest恢复；N-01整zone不能借N-07授权，N-02/N-03精确agent-instance机制待核，A-02数据独占可重建/删除恢复另审。 | P-02 Validated still AwaitingAuthorization; V-09 requires broker/indirect-consumer/guest-recovery checks. N-01 whole-zone scope cannot reuse N-07 approval, N-02/N-03 exact agent-instance mechanisms need qualification, A-02 exclusivity/reconstructibility/deletion-recovery separate review. |
| 真实不兼容 / Evidenced incompatibility | S-03当前ZRS无geo-failover前置；A-04无geo links可unlink。仅对应variant Blocked，不迁SKU/新建geo成员补覆盖。 | S-03 current ZRS lacks geo-failover prerequisites; A-04 has no geo links to unlink. Only affected variants are Blocked; no SKU migration/new geo members for counts. |
| 原生未映射 / Native-unmapped | node/network/mesh、精确VM路径/卷/进程、客户端/时序/递增泄漏等按唯一清单暂缓；I-01目标AwaitingTarget/机制PendingDesign，不安装mesh或模拟补齐。 | Defer node/network/mesh, exact VM path/volume/process, client/timing/progressive-leak mechanisms per canonical catalog; I-01 AwaitingTarget/PendingDesign, no mesh installation or simulations for coverage. |

准备状态分清PendingConfiguration、AwaitingTarget、PendingPrerequisite、PendingVerification、PendingDesign、PendingValidation、Validated、AwaitingAuthorization和有证据Blocked；未运行NotRun，不整campaign blanket Blocked。Validated不是故障/完整infra/business通过，历史空namespace与“未执行”不能覆盖最新事实。
Distinguish PendingConfiguration, AwaitingTarget, PendingPrerequisite, PendingVerification, PendingDesign, PendingValidation, Validated, AwaitingAuthorization and evidenced Blocked. Unexecuted means NotRun, not blanket campaign Blocked. Validated is not fault/full infra/business acceptance; historical empty namespaces and “not executed” statements do not override current facts.

<a id="1-coverage-review"></a>
## 1. 现有覆盖与资源归属 / Existing Coverage and Ownership

基础设施是已接受的起点，不因旧缺模块/Provider下载失败记录重建。下面为源码能力与后续缺项，部署/资格看当前证据，原生九项成功不认证完整业务。
Infrastructure is the accepted starting point; do not rebuild because of historical missing-module/provider-download records. The following separates source capability from remaining work; deployment/qualification require current evidence, and nine native successes do not certify business resilience.

| 部分 / Area | 中文已实施能力与缺项 | Corresponding English implemented capability and gaps |
| --- | --- | --- |
| [Chaos stack](../stacks/chaos/main.tf) / [module](../modules/chaos/main.tf) | Workspace/UAMI/discovery、精确service-direct配置/权限，无run资源；所选配置已验证，新增case仍核region/schema/eligibility/权限。 | Workspace/UAMI/discovery and exact service-direct configurations/rights, no run resource; selected configurations validated, new cases still require regional schema/eligibility/permissions. |
| [Provider baseline](../version.tf) | AzureRM4.55.0/AzAPI2.14.0及stage locks保留；不沿用旧3.115.0/2.7.0结论，不为onboarding升级/改backend。 | Preserve AzureRM4.55.0/AzAPI2.14.0 and stage locks; do not reuse obsolete3.115.0/2.7.0 conclusions or upgrade/change backend for onboarding. |
| [AKS module](../modules/aks/main.tf) / [Pod definitions](../modules/chaos/pods.tf) | private/OIDC/Workload Identity/Azure RBAC和五typed bounded Actions已实现；实际version/architecture/image/admission/network/private preview与目标命中未验收，不重复installer资源。 | Private/OIDC/Workload Identity/Azure RBAC and five typed bounded Actions implemented; actual version/architecture/image/admission/network/private-preview/target impact unaccepted, no duplicate installer assets. |
| PaaS/VM | catalog含SQL、两Redis、消息、Storage、Cosmos、VM/VMSS；支持不等于选定目标资格，精确实体、产品、agent/HA/geo须逐Action核验。 | Catalog includes SQL/both Redis/messaging/Storage/Cosmos/VM/VMSS; support is not target eligibility. Verify exact entities/product/agent/HA/geo per Action. |
| [Probe](../modules/chaos-validation/probe.py) / [stop](../modules/chaos-validation/stop.py) | concurrent phased HTTPS/latency/observation、可选live records/read-only stop signal；真实协议/业务、独立ledger/monitor通知、integrity/backlog观察与持续恢复尚未完成。 | Concurrent phased HTTPS/latency/observation, optional live records/read-only stop signal; real protocols/business, independent ledgers/monitor notification, integrity/backlog observation and sustained recovery remain incomplete. |
| [Reference clients](../modules/chaos-validation/business.py) / [ledger](../modules/chaos-validation/ledger.py) / [campaign gates](../modules/chaos-validation/campaign.py) | Blob S-01、SB B-01/B-02/B-04有限合成准备、crash-safe账本/manifest/window；不是完整应用/故障实现。声明Job仍probe.py，打包不启动流量。 | Bounded synthetic Blob S-01/SB B-01/B-02/B-04 preparation, crash-safe ledger/manifest/windows; not complete apps/fault implementations. Declared Job still runs probe.py; packaging starts no traffic. |
| Safety tests | 实体/目标/Pod/measurement约束与独立stop测试已有；mock/unit只证明各自scope，不证明Azure支持/真实流量/恢复。 | Entity/target/Pod/measurement constraints and independent stop tests exist; mocks/units prove their scope only, not Azure support/traffic/recovery. |

### 1.1 资源与 state 归属 / Resource and state ownership

| Owner | 中文职责与边界 | Corresponding English responsibility and boundary |
| --- | --- | --- |
| Terraform Chaos state | Workspace/runtime identity/discovery、service-direct Scenarios/configurations和已审target权限；原state/完整输入不变，不运行故障。 | Workspace/runtime identity/discovery, service-direct Scenarios/configurations and reviewed target rights; preserve original state/full inputs, no fault execution. |
| Operator installation | extension、subscriber identity/federation、cluster-scope Chaos Kubernetes Extension Operator grant、Workspace connection；Terraform只引用，不重复role/identity/connection/Helm。 | Extension, subscriber identity/federation, cluster-scope Chaos Kubernetes Extension Operator grant and Workspace connection; Terraform references, not duplicates roles/identities/connections/Helm. |
| Platform / Cluster | 保持独立state/backend mapping/原资源；Workspace onboarding跳Cluster，ingress/Argo CD/验证Jobs关闭。不全量Platform apply、backend迁移或空state掩盖问题。 | Separate states/backend mapping/existing assets; Workspace onboarding skips Cluster with ingress/Argo CD/verification Jobs off. No full Platform apply/backend migration/empty-state concealment. |
| 未来adoption / Future adoption | installer声明式接管先parity/import/ownership审查；Portal-owned Workspace不得启当前creating module覆盖，需批准adoption或existing-Workspace input，后者尚未实现。 | Declarative installer adoption requires parity/import/ownership review; never enable creating module over portal-owned Workspace. Approve adoption or existing-Workspace inputs first; reference mode is currently unimplemented. |

<a id="2-installation-decisions-to-settle-first"></a>
## 2. AKS 安装与兼容边界 / AKS Installation and Compatibility

Chaos Studio是托管服务，Workspace创建与AKS extension安装是不同操作，不是通用Helm部署。已有extension不重装来满足历史缺项；下列清单用于复核或未来明确获批安装。
Chaos Studio is managed; Workspace creation and AKS extension installation are separate, not general Helm deployment. Do not reinstall existing extensions to satisfy historical gaps; use these checks for requalification or explicitly approved future installation.

| 检查 / Check | 中文要求 | Corresponding English requirement |
| --- | --- | --- |
| Namespace | 安装前独立target namespace，显式experiments.targetNamespaces，不能default/system/control；当前官方改名单需卸载重装，生命周期另审。 | Dedicated target namespace and explicit experiments.targetNamespaces before installation, not default/system/control. Current documented list changes require uninstall/reinstall and separate lifecycle review. |
| 三类隔离 / Three boundaries | chaos-infrastructure控制组件、可恢复target、故障外control/verification/ledger/recovery分离；当前原生阶段不因此新建应用。 | Separate chaos-infrastructure control components, recoverable targets and outside-fault control/verification/ledger/recovery; this does not require new apps in current native phase. |
| Admission | verification namespace保持PSA restricted；restricted target会拒pod-delete helper，必要例外仅专用target namespace获批，不放宽全cluster。 | Keep verification namespace PSA restricted; restricted targets reject pod-delete helpers. Any necessary exception is approved narrowly for dedicated targets, not whole-cluster relaxation. |
| Region/平台 / Region/platform | Workspace region/data residency独立核target；非生产Linux amd64可调度容量、OIDC/WI/Azure RBAC/user auth/version及private API/DNS当前可用。 | Qualify Workspace region/data residency separately from targets; non-production schedulable Linux amd64, OIDC/WI/Azure RBAC/user auth/version and current private API/DNS access. |
| 工具版本 / Tool versions | 固定获批k8s-extension CLI≥1.9.5与已验证extension版本，记录实际版本，不blind latest/upgrade；从官方源核hash，不改全局工具绕过。 | Pin approved k8s-extension CLI≥1.9.5 and verified extension version, record actual versions, no blind latest/upgrade; verify official hashes, no global-tool workaround. |
| 网络与权限 / Network/rights | Workspace regional data plane/Entra/images出站、Deployment Safeguards/network daemon资格；安装/运行/operator分离，内置cluster grant不由service-direct custom map重复。不开放公网API/inbound。 | Qualify outbound Workspace regional data plane/Entra/images and Deployment Safeguards/network daemon; separate install/runtime/operator rights, no duplicate built-in cluster grant via service-direct custom map. No public API/inbound workaround. |
| private preview | 官方private clusters未验证，不等于永久不支持；隔离非生产短故障功能资格另授权。Provisioning/Ready/connection Pending只安装证据，真实impact才功能证明；PaaS/客户端独立合格可继续。 | Officially unvalidated private clusters are not permanently unsupported; separately approve isolated non-production short-fault qualification. Provisioning/Ready/connection Pending are installation evidence; actual impact proves function. Independently eligible PaaS/client paths may proceed. |

<a id="3-dependency-ordered-implementation"></a>
## 3. I0–I7 依赖与完成状态 / I0–I7 Dependencies and Status

保留原英文I0–I7完整工程路径。以下依赖用于完整infra/business实施；当前已完成原生单Action路径见§0，不把I2全量业务建设加为原生新前置。实施批准与部署/运行批准分离。
Retain the former English I0–I7 full engineering path. These dependencies govern full infra/business implementation; completed native single-Action work is in §0 and does not gain a new full-business I2 prerequisite. Implementation approval is separate from deployment/execution approval.

| Task / Dependency | 中文交付与出口证据 | Corresponding English deliverable and exit evidence |
| --- | --- | --- |
| I0 / 无 / None | scope/ownership私有manifest：case/variant/phase、精确ID/entity、region/SKU、state/exclusions/operator/cost/window/恢复/SLO-RTO-RPO，确认Workspace create/adopt；无重复归属、平台只引用，缺资格按case记录。 | Private scope/ownership manifest: cases/variants/phases, exact IDs/entities, region/SKU, state/exclusions/operator/cost/window/recovery/SLO-RTO-RPO and Workspace create/adopt choice; no duplicate ownership, platform reference-only, per-case eligibility gaps. |
| I1 / I0 | locked Provider/API核现有Chaos stack、Workspace-only/discovery配置，只有需要时评existing path；静态通过、private plan仅owned Chaos，部署后发现匹配manifest。 | Validate existing Chaos stack with locked Providers/API, Workspace-only/discovery configuration and existing-reference path only if needed; passing static checks, private owned-only Chaos plan and post-deployment discovery matching manifest. |
| I2 / I0 | phased concurrent control/canary、真实flow/identity、独立durable evidence/ledger/threshold/recovery，target namespace/canary另准备；授权无故障基线证明实际flow/不变量/容量/恢复，Job不授通用fault-start。 | Phased concurrent control/canary, real flows/identities, independent durable evidence/ledgers/thresholds/recovery and separately prepared target namespace/canary; approved baseline proves flows/invariants/capacity/recovery, no general fault-start rights on Jobs. |
| I3 / I1+I2 target namespace | operator按明确namespace/固定版本安装或复核已有extension，登记installer资源/compatibility；provisioning/pods/component正常、无重复归属，私有功能另测。 | Operator installs or rechecks extension with exact namespaces/pinned versions, records installer-owned assets/compatibility; healthy provisioning/Pods/components, no duplicate ownership, separately test private functionality. |
| I4 / I1 | per-Action serialization/entity/database/enum/semantics/target/RBAC硬约束与真实region核验；mocks拒empty/wildcard/malformed，cloud Validate解析精确获批目标。 | Harden per-Action serialization/entities/database/enums/semantics/targets/RBAC and verify region; mocks reject empty/wildcard/malformed input, cloud Validate resolves exact approved targets. |
| I5 / I1+I3 | distinct typed Pod path引用原extension，externalResource/Scenario/config binding、namespace AND labels、duration/intensity、默认off，保留service-direct、无run。 | Distinct typed Pod path referencing existing extension, correct externalResource/Scenario/config bindings, namespace AND labels, duration/intensity and default-off behavior; preserve service-direct, no run. |
| I6 / I2+适用I4或I5 / applicable I4 or I5 | 完整阶段配置/流量/run另授权后每次一故障，基线/实际impact/stop/recovery/对账；case完整phase结论、隔离/持续恢复/private drift。 | For full phases, separately approve configuration/traffic/run, one fault with baseline/actual impact/stop/recovery/reconciliation; complete phase verdict, containment/sustained recovery/private drift. |
| I7 / 相关I6干净恢复 / clean relevant I6 recovery | 逐case扩Pod stress/network、DB HA、VM/VMSS与可选destructive/DR；独立配置/窗口/前置/授权，不自动加压、重叠或重复不可逆操作。 | Expand Pod stress/network, DB HA, VM/VMSS and optional destructive/DR per case; independent configuration/window/prerequisites/approval, no auto-escalation/overlap/irreversible repeats. |

I1/I2可在I0后并行；I4不依赖I3/I5，Pod兼容失败不阻塞合格service-direct/client。职责owner需明确，不能凭表格推云端授权。
I1/I2 may progress after I0 in parallel; I4 does not depend on I3/I5, and Pod compatibility failures do not block eligible service-direct/client paths. Name responsible owners explicitly; the table implies no cloud approval.

### 3.1 当前任务状态 / Current task status

| Task | 中文状态与剩余出口 | Corresponding English status and remaining exit |
| --- | --- | --- |
| I0 | 本轮原生9项scope/授权已有执行记录；完整阶段manifest/真实flow/数字契约/cost/recovery仍Partial，新分支逐项核验。 | Executed native nine-case scope/approval is recorded; full-phase manifest/real flows/numeric contracts/cost/recovery remain Partial, new branches require per-case verification. |
| I1 | 已装Workspace、发现/12配置精确原生Validate与replan完成；新增目标/region/权限仍单独核验，existing-Workspace mode未实现。 | Workspace installed, discovery/12 exact native validations/replan completed; new targets/regions/rights need separate verification, existing-Workspace mode unimplemented. |
| I2 | availability/evidence/stop、Blob/SB reference/ledger/manifest/windows已写，整体Partial；实际app/其余协议、durable独立storage、monitor freshness/通知、云基线/恢复演练未完成。 | Availability/evidence/stop and Blob/SB reference/ledger/manifest/windows implemented, overall Partial; real app/other protocols, independent durable storage, monitor freshness/notification and cloud baseline/recovery rehearsal incomplete. |
| I3 | extension安装完成，private功能/实际Pod匹配与当前观察路径PendingVerification；不重复安装。 | Extension installation complete, private functionality/actual Pod matches/current observation path PendingVerification; no reinstall. |
| I4 | 严格serialization/inputs与所选12配置原生Validate完成；整体新增Action/target资格仍Partial，mock不能证明全部catalog可用。 | Strict serialization/inputs and 12 selected native validations complete; new Action/target qualification still Partial, mocks do not prove the whole catalog. |
| I5 | 五typed Pod definitions已实现；获批动态target、image/admission/private功能/实际containment未验收。 | Five typed Pod definitions implemented; approved dynamic targets, image/admission/private function and actual containment unaccepted. |
| I6 | 原生PaaS两轮已执行并报告，不能再写整体“未执行”；完整infra/business出口未满足，Redis影响Inconclusive、AKS/VM等NotRun，扩展风险另审。 | Two native PaaS rounds executed/reported, so blanket “not executed” is obsolete. Full infra/business exit unmet, Redis impact Inconclusive, AKS/VM etc. NotRun, expanded risks separately reviewed. |
| I7 | 后续追加，部分原生HA机制已执行不等于全部扩展完成；每分支等相关恢复证据、资格与新授权。 | Follow-up scope; executed native HA mechanisms do not complete all expansion. Each branch awaits relevant recovery evidence/eligibility/new approval. |

<a id="4-recommended-execution-waves"></a>
## 4. 后续执行批次 / Follow-up Execution Waves

保留原英文waves作为未来完整阶段建议，不能覆盖§0两轮实际结果，也不授权再次执行。详细case/数值/边界仍以唯一清单为准，一次一故障。
Retain the former English waves as future full-phase guidance, not overrides of §0 actual results or rerun authorization. The canonical catalog governs detailed cases/numeric boundaries, with one fault per run.

| Wave | 中文计划与额外门槛 | Corresponding English plan and additional gates |
| --- | --- | --- |
| 0 无故障 / No fault | 所选服务真实应用/control、identity refresh、ledger、恢复演练；实际健康流与完整证据，不用ping通过。 | Real application/control, identity refresh, ledgers and recovery rehearsal for selected services; healthy actual flow and complete evidence, not pings. |
| 1 最小影响 / Minimal impact | C-01/A-01 cache client、单专用SB queue/EH entity、合格K-01；只选一，精确实体/原状态、private兼容、真实impact/restoration。 | C-01/A-01 cache-client, one dedicated SB queue/EH entity or qualified K-01; select one, exact entities/prior states/private compatibility and actual impact/restoration. |
| 2 恢复 / Recovery | C-02、M-02、Legacy副本reboot、P-01、另选RocketMQ VM restart；各自数据/HA/recovery，Legacy不套Managed Redis，broker需service/ack非Running。 | C-02, M-02, Legacy replica reboot, P-01 and separately selected RocketMQ VM restart; per-case data/HA/recovery, never Managed Redis substitution, broker service/ack proof rather than Running. |
| 3 压力/节点 / Pressure/nodes | Pod CPU/memory/latency/loss、获批User VMSS shutdown、planned干净恢复后forced；核image/preview/容量/副本/autoscaler/storage，排System/恢复。VMSS zone可能全部实例，非天然单节点或完整zone故障。 | Pod CPU/memory/latency/loss, approved User VMSS shutdown and forced failover after clean planned recovery; qualify images/preview/capacity/replicas/autoscaler/storage, exclude System/recovery. VMSS zone can affect every instance, not inherently one node/full-zone outage. |
| 4 destructive/DR opt-in | Managed Redis flush/unlink、Storage planned、PITR/geo、另选Cosmos offline-region；独立合成数据/backup/replication/impact/cost/window/不可逆许可，不为矩阵新建Cosmos/geo fixture。 | Managed Redis flush/unlink, Storage planned, PITR/geo and separately selected Cosmos offline-region; dedicated synthetic data/backup/replication/impact/cost/window/irreversible approval, no Cosmos/geo fixtures for matrix counts. |

Managed Redis无已确认直接reboot Action；Storage failover全账户非container；DNS/blackout未来仅获批canary hook/protocol proxy，不改共享NSG/DNS/private endpoints。完整business/未来LB-Gateway分别按追加计划推进，不称70用例全部通过。
No direct Managed Redis reboot Action is confirmed; Storage failover is account-wide, not container-scoped. Future DNS/blackout uses approved canary hooks/protocol proxies only, not shared NSG/DNS/private-endpoint changes. Progress full business/future LB-Gateway separately under follow-up plans, never claiming all 70 cases passed.

<a id="5-verification-and-case-acceptance"></a>
## 5. 验证与交付要求 / Verification and Delivery

### 5.1 配置与开发验证 / Configuration and development validation

仅变更scope用既有locked工具：fmt、需要时init -backend=false -lockfile=readonly、validate、相关mock/plan/unit、固定TFLint/既有policy工具；未运行扫描明确记录，不global suppress。新增行为tests覆盖default-off/外部binding/namespace-label escape/duration-intensity/malformed entity/excluded target/精确RBAC、HTTP成功但latency越限/concurrent observations/unknown ack。真实apply tests须另授权。
Use the existing locked toolchain on changed scopes only: fmt, init -backend=false -lockfile=readonly when needed, validate, targeted mocks/plans/units, pinned TFLint/existing policy tool. Explicitly record unrun scans, no global suppressions. Tests cover introduced default-off/external binding/namespace-label escapes/duration-intensity/malformed entities/excluded targets/exact RBAC, latency breaches despite HTTP success/concurrent observations/unknown acks. Real apply tests need separate approval.

部署用原正确backend/完整私有输入保存审新plan；意外平台变更、RBAC扩大、公网、delete/replace、重复归属即停，只apply获批同一saved plan。backend-disabled init不是部署就绪；旧初始空Scenario只适用于首次准备，不能覆盖当前state。
Deployment uses the original correct backend/full private inputs and a fresh reviewed saved plan. Stop for unexpected platform changes/widened RBAC/public access/deletes/replacements/duplicate ownership; apply only the same approved plan. Backend-disabled init is not deployment readiness; initial empty Scenarios cannot overwrite current state.

### 5.2 运行与完整阶段验收 / Runtime and full-phase acceptance

下列原英文建议保留给完整business阶段，不是Microsoft SLA或本轮原生新门槛，执行前按真实契约确认。
Retain these former English proposals for full business phases, not Microsoft SLAs or new current native gates; confirm actual contracts before execution.

| 项目 / Item | 中文验收要求 | Corresponding English acceptance |
| --- | --- | --- |
| 基线 / Baseline | 15分钟、至少1000相关操作，建议≥99.9%且满足latency SLO，低量延长。 | 15 minutes and ≥1,000 relevant operations, proposed ≥99.9% within latency SLO; extend low-volume windows. |
| 暴露 / Exposure | 初始模拟60秒、单canary/依赖；Discrete实测outage，不假定duration就是中断。 | Initial simulation 60 seconds, one canary/dependency; measure Discrete outage, never infer it from duration. |
| 依赖失败 / Dependency failure | deadline明确失败或契约durable queue，无假成功；control保持基线。 | Explicit deadline failure or contractual durable queue, no false success; control stays within baseline. |
| 恢复 / Recovery | 短模拟移除后建议120秒回SLO并持续10分钟/逐窗口；incident RTO与removal-to-recovery分开。 | Proposed short-simulation recovery within 120 seconds after removal, sustained ten minutes/windowed; separate incident RTO from removal-to-recovery. |
| 完整性 / Integrity | 每ack持久操作对账、unknown解决、无重复committed业务effect；cache-only数据非durability保证。 | Reconcile every acknowledged durable operation/resolve unknowns/no duplicate committed business effects; cache-only data is not a durability guarantee. |
| targeting/API | 每次最新Validate、resolved/excluded对私有manifest、动态Pod/实例重查；旧CLI create/update不支持resourceTargeting，用已核固定API，不drop targeting字段或自动修权限。 | Latest Validate each run, compare resolved/excluded against private manifest and recheck dynamic Pods/instances; old CLI create/update lacks resourceTargeting, use verified pinned API without dropping fields/auto-repairing permissions. |
| stop/recovery | 未授权影响/control SLO/integrity/retry-backlog-capacity/窗口超限或恢复访问丢失即独立operator停；noncancelable不undo。network Succeeded也实测连通，替换受影响测试Pod需恢复授权，不destroy。 | Independent operator stops on unauthorized impact/control SLO/integrity/retry-backlog-capacity/window overrun/lost recovery access; noncancelable cannot undo. Prove network connectivity even after Succeeded; affected test-Pod replacement needs recovery approval, no destroy. |
| 报告 / Report | case/hypothesis/authorization、baseline/target/impact/timeline、Chaos+events/service+app metrics+ledger、stop/recovery/window/drift；真实ID/端点/request-run/raw只私有。 | Case/hypothesis/authorization, baseline/targets/impact/timeline, Chaos+events/service+app metrics+ledger, stop/recovery/windows/drift; actual IDs/endpoints/request-run/raw evidence private only. |

结果用Passed/Failed/Inconclusive/Blocked，中文依据配英文；准备缺项用具体状态+execution=NotRun，已证实不兼容/复现未解preflight才Blocked。原生Succeeded或管理面Passed不关闭完整infra/business，未执行/缺影响/缺证据不能成功。
Use Passed/Failed/Inconclusive/Blocked with Chinese rationale and corresponding English. Preparation gaps use specific status+execution=NotRun; Blocked requires evidenced incompatibility/reproduced unresolved preflight. Native Succeeded/management-plane Passed does not close full infra/business; unexecuted/missing impact/evidence cannot pass.

<a id="6-first-deliverable-and-deferred-scope"></a>
## 6. 原英文计划保留的后续追加 / Retained Follow-up Plans

原“首交付”是安装/单配置/基线harness建议，现Workspace/extension/12配置与九项原生运行已完成；不再次要求从零交付。以下保留原英文尚未完成的全部工程分支，按已有中文实施主线后续追加；仅在用户选择对应完整阶段/目标并授权时执行。
The former first-deliverable recommendation covered installation/single configuration/baseline harness. Workspace/extension/12 configurations and nine native cases now exist; do not restart delivery from zero. Retain every incomplete former English engineering branch below as follow-up to the actual Chinese-led implementation, executing only when its full phase/targets are selected and approved.

| 后续追加 / Follow-up | 中文保留计划与边界 | Corresponding English retained plan and boundary |
| --- | --- | --- |
| I2：完整测量与停止 / Full measurement/stop | 基于现harness补真实protocol/business flow、workload身份、独立durable ledger/cloud storage、retry/backlog/integrity observer、operator通知/检测预算、云baseline/recovery演练；sample-window stop不是持续time-window恢复或自动Cancel。 | Extend existing harness with real protocol/business flows, workload identities, independent durable ledger/cloud storage, retry/backlog/integrity observers, operator notification/detection budgets and cloud baseline/recovery rehearsals; sample-window stop is not sustained recovery or automatic Cancel. |
| I2：阶段Job / Phased Jobs | 已有900秒Job放不下15分钟baseline+fault+10分钟recovery，采用获批有限phase/deadline/连续证据/TTL前导出；固定验证image/ConfigMap脚本、requests/limits/least privilege、保持Job默认off。当前不建canary补原生。 | Existing 900-second Job cannot fit 15-minute baseline+fault+ten-minute recovery. Use approved finite phases/deadlines/continuous evidence/export before TTL, pinned validated images/ConfigMaps/requests/limits/least privilege, Jobs default off. Do not add canaries for current native work. |
| I2：reference到真实应用 / Reference-to-app | 只补首选case需要的协议，Blob/SB合成准备不称真实app；后续真实订单/库存/cache-aside/outbox、ack/unknown/唯一effect、settlement/checkpoint与十窗口恢复接应用契约。 | Add only protocols needed by selected first cases; synthetic Blob/SB preparation is not real apps. Later integrate order/inventory/cache-aside/outbox, ack/unknown/unique effects, settlement/checkpoint and ten-window recovery with actual app contracts. |
| I4：新增Action/目标 / New Actions/targets | 复用[Chaos module](../modules/chaos/)与[stack](../stacks/chaos/)，不第二orchestration framework；malformed/non-list/non-string/blank/wildcard拒绝，逐region核database/entity/enum/serialization/rights/target。结构duration必填包括Discrete，不等于effect/outage/可取消。 | Reuse Chaos module/stack, not another orchestration framework. Reject malformed/non-list/non-string/blank/wildcard entities; verify regional database/entity/enums/serialization/rights/targets. Structural duration remains required for Discrete, not effect/outage/cancelability. |
| I3/I5：Pod实际资格 / Pod runtime qualification | distinct extension path version1.0.0/externalResource，安装namespace allowlist+精确AND restrictive labels/排system-control-verification，container/amd64工具/admission/private预览；每run动态preview。graceful delete明确percentage/interval/最大set，不100%；duration≥PT1M且≥durationSeconds，初始effect≤60秒；CPU/memory需shell/utilities，network loss不默认100%。 | Distinct extension path version1.0.0/externalResource, installation namespace allowlist+exact restrictive AND labels/system-control-verification exclusion, containers/amd64 tools/admission/private preview; dynamic preview each run. Graceful delete with exact percentage/interval/max set, not100%; duration≥PT1M and≥durationSeconds, initial effects≤60 seconds; CPU/memory require shell/utilities, network loss not default100%. |
| I7：VM/VMSS与压力 / Compute expansion | V-03/V-04已有definition与16 regional Action/resource pairs核验保留，执行前VM身份/出站/headroom；VMSS agent精确instance scope另核，不以Pod-only作用替node，不导入AKS生命周期。 | Retain V-03/V-04 definitions and recorded16 regional Action/resource pairs; verify VM identity/outbound/headroom before execution. Separately qualify exact VMSS-agent instance scope, no Pod-only substitution for nodes or AKS lifecycle import. |
| I7：destructive/DR | flush/unlink/PITR/storage/geo/zone各自data-loss/backup/replication/cost/window/recovery授权；不默认full-zone、多regionfixture、cache清空/自动schedule。Cosmos/RocketMQ业务未选，LB/Gateway无目标Future，之后选中才追加。 | Per-case flush/unlink/PITR/storage/geo/zone data-loss/backup/replication/cost/window/recovery approval; no default full-zone/multi-region fixtures/cache erasure/automatic schedules. Cosmos/RocketMQ business unselected, LB/Gateway targetless Future, append only after selection. |
| ownership/adoption | 需要时才实现existing-Workspace input或installer declarative adoption，先parity/import/ownership审查；不重复role/identity/connection/Helm，不bundle平台重建/backend迁移/provider升级/classic fallback/全局policy放宽。 | Implement existing-Workspace inputs/installer declarative adoption only when needed, after parity/import/ownership review. No duplicate roles/identities/connections/Helm, bundled platform rebuild/backend migration/Provider upgrade/classic fallback/global-policy relaxation. |
| I6/I7：最终完整报告 / Final full report | 对选定variant/phase取得真实impact/containment/data/sustained recovery/private drift再更新完整报告；即使失败或证据不足也如实报告，不等全矩阵成功才写报告，不把本地mock或platform Available替代。 | Update full reports after actual impact/containment/data/sustained recovery/private drift for selected variants/phases; report failures/gaps honestly without waiting for the whole matrix to succeed. Local mocks/platform Available are not substitutes. |

### 6.1 本次文档整理完成条件 / Completion of this documentation edit

- [x] 中文实际进度在前，英文逐段/逐表对应。 / Chinese actual progress leads, with matching English paragraphs/tables.
- [x] 原I0–I7、安装/ownership、waves与所有额外工程分支保留。 / Original I0–I7, installation/ownership, waves and all additional engineering branches retained.
- [x] 两轮原生结果与完整infra/business未验收分开，不再整体写“未执行故障”。 / Two native rounds separated from unaccepted full infra/business, no blanket “faults not executed.”
- [x] 历史检查与最新结果分栏，不把旧private可达/空workload当当前证据。 / Historical checks separated from current results; old private reachability/empty workloads are not current evidence.
- [x] 不修改Terraform、runbook、运行脚本或云资源，不新增执行授权。 / No Terraform/runbook/runner/cloud changes or new execution approval.

<a id="7-historical-batches"></a>
## 7. 历史工程批次证据 / Historical Engineering Evidence

以下保留原英文全部工程批次检查，计数分别属于当时scope，不能相加成当前覆盖率或称本次重跑；“未云端执行”只描述该历史批次。mock临时精确version overrides/缓存Provider未改repository locks，TFLint/Checkov未运行的批次不借旧pass补齐。
Retain all former English batch checks below. Counts belong to their historical scopes, not additive current coverage or fresh reruns. “No cloud execution” describes that batch only. Temporary exact-version mock overrides/cached Providers did not alter repository locks; batches without TFLint/Checkov do not inherit earlier passes.

| 历史批次 / Batch | 中文检查与限制 | Corresponding English checks and limitations |
| --- | --- | --- |
| 初始configuration-only | service-direct严格实体、五Pod typed definitions、optional concurrent phased HTTPS/latency/observations。fmt/root/Cluster/Chaos/module validate通过；39 mocks（27 module+3 stack+9 verification），9 probe tests/两Python syntax通过。 | Strict service-direct entities, five typed Pod definitions, optional concurrent phased HTTPS/latency/observations. Formatting/root/Cluster/Chaos/module validation passed;39 mocks（27 module+3 stack+9 verification）, nine probe tests/two Python syntax checks passed. |
| 初始scan与云边界 / Initial scans/cloud boundary | TFLint0.59.1无error、两pre-existing required_version warnings；offline Checkov3.2.495五适用checks过/零失败，不证明AzAPI fault资格；该批无plan/apply/extension install/traffic/fault/recovery。 | TFLint0.59.1 no errors/two pre-existing required_version warnings; offline Checkov3.2.495 five applicable checks passed/zero failed, not AzAPI fault eligibility. No plan/apply/extension installation/traffic/fault/recovery in that batch. |
| I2 evidence/stop | opt-in flushed versioned records+独立finite availability evaluator，Terraform只打包/传streaming，不启动monitor/fault，legacy report/default-off Job保留。26 Python tests（producer-consumer/live silence无EOF/corrupt-incomplete/threshold）、9 mocks、Cluster validate/HCL fmt、Pylance syntax/signature通过。 | Opt-in flushed versioned records+independent finite availability evaluator; Terraform packages/forwards streaming only, no monitor/fault, preserving legacy report/default-off Jobs.26 Python tests（producer-consumer/live silence without EOF/corrupt-incomplete/threshold）, nine mocks, Cluster validate/HCL formatting and Pylance syntax/signature passed. |
| I2未执行 / I2 unexecuted work | 该批无backend迁移/Azure plan/deploy/真实app；TFLint/Checkov工具缺失未重跑，cloud baseline/monitor通知/fault/business recovery未执行，I2及完整I6未完成。 | No backend migration/Azure plan/deploy/real app in that batch; TFLint/Checkov unavailable, not rerun. Cloud baseline/monitor notification/fault/business recovery unexecuted, I2/full I6 incomplete. |
| Blob/SB reference | 61+2 Python/offline SDK tests；9 verification mocks用Kubernetes2.38.0/hash，probe-only/off Job不变；Root/Bootstrap/Cluster/Chaos validate与recursive fmt/whitespace通过，Bootstrap只核AzAPI checksum非upgrade。 | 61+2 Python/offline SDK tests; nine verification mocks using Kubernetes2.38.0/hash with probe-only/off Jobs retained. Root/Bootstrap/Cluster/Chaos validation and recursive formatting/whitespace passed; Bootstrap only received verified AzAPI checksum, not upgrade. |
| SDK/依赖 / SDK/dependencies | Python3.12 hash-verified resolution通过，非3.12 runtime认证；17 runtime pins查GitHub pip advisories零matching，modernization工具不支持Python，不称源码/image安全认证。该批无SDK流量/fault。 | Python3.12 hash-verified resolution passed, not3.12 runtime certification;17 runtime pins checked against GitHub pip advisories with zero matches, modernization tool unsupported for Python, no source/image security certification. No SDK traffic/fault in that batch. |
| 历史private transport | AKS Succeeded/Running/Available非workload证据。isolated non-admin context核目标、本地DNS失败，已有VM管理通道CA/TLS hostname+401仅transport；修token互斥subscription/tenant参数后取token成功，但ARM gateway400/BadRequest因Run Command关闭，无改cluster。 | AKS Succeeded/Running/Available was not workload evidence. Isolated non-admin context confirmed target/local DNS failure; existing VM channel CA/TLS hostname+401 proved transport only. After correcting mutually exclusive subscription/tenant token arguments, token acquisition succeeded but ARM gateway400/BadRequest reflected disabled Run Command, with no cluster changes. |
| 2026-11-23历史认证与清理 / Historical authenticated access/cleanup | 获批temporary MI从已有VM，隔离SHA256核kubectl1.36.5/kubelogin0.2.18；private readyz、4/4 nodes、6/6控制pods Ready、OIDC/WI/RBAC。只Cluster User/RBAC Reader/custom registered nodes/read，无admin/write/secret；temporary identity+3assignments+custom role五资源清理，guest工具/credentials清、原VM identity恢复。 | Approved temporary MI from existing VM with isolated SHA256-verified kubectl1.36.5/kubelogin0.2.18; private readyz,4/4 nodes,6/6 control Pods Ready, OIDC/WI/RBAC. Only Cluster User/RBAC Reader/custom registered nodes/read, no admin/write/secret; clean identity+three assignments+custom role（five assets）, guest tools/credentials, restore original VM identity. |
| 历史access验收限制 / Historical access limitation | 当时target namespace无workload、verification不存在，未运行业务/fault；私网授权/Ready非完整验收，清理后不宣称当前访问仍可用。72 local/mock checks非完整通过；当前private阻塞以报告§8/本文§0为准。 | Then target namespace had no workloads/verification was absent, no business/fault run. Approved private access/Ready were not full acceptance, and cleanup does not imply current access still works.72 local/mock checks were not full passes; current private limitations follow report§8/§0 here. |
| Infra-first definition批次 / Definition batch | V-03/V-04默认off、70 case registry同步；UK South16 Action/resource pairs及推荐pressure keys/casing核验，raw私有。8 pressure mocks+27 existing Chaos mocks+4stack mocks、63 Python tests通过；新ID识别/拒undefined/缺资格仍拒，不新增协议或授权。 | V-03/V-04 default-off and70-case registry synchronized; UK South16 Action/resource pairs/recommended pressure keys/casing verified, raw private. Eight pressure mocks+27 existing Chaos mocks+four stack mocks,63 Python tests passed; recognize new IDs/reject undefined IDs/missing qualification, no new protocols/approval. |
| Infra-first静态/云边界 / Static/cloud boundary | AzureRM4.55.0/AzAPI2.14.0 module/stack validate、HCL fmt/whitespace、70 registry一致/Pylance syntax通过；isolated copy仅适配lock约束、原版本/hash/locks未变。TFLint/IaC tools缺失未执行；该批无apply/HA migration/新IAM/agent/traffic/fault，非后续原生未执行声明。 | AzureRM4.55.0/AzAPI2.14.0 module/stack validation, HCL formatting/whitespace,70-case registry consistency/Pylance syntax passed. Isolated copy adapted lock constraints only, original versions/hashes/locks unchanged. TFLint/IaC tools unavailable; no apply/HA migration/new IAM/agent/traffic/fault in that batch, not a claim about later native runs. |
| 原生binding回归 / Native-binding regression | 35 Chaos mocks+4stack mocks、stack validate/recursive fmt/whitespace通过；当前native云Validate与实际fault另见§0，不以mock替代。 | 35 Chaos mocks+four stack mocks, stack validation/recursive formatting/whitespace passed; native cloud validation/actual faults are in§0, not replaced by mocks. |
| 历史operator安装 / Operator installation | extension0.1.12、required components Ready、专用空namespace、当时零用户configuration/no fault-business Jobs；connection Pending已知preview issue，不是失败或功能证明。后续12配置/两轮run已更新§0。 | Extension0.1.12, required components Ready, dedicated empty namespace, then zero user configurations/no fault-business Jobs; connection Pending known preview issue, neither failure nor functional proof. Subsequent12 configurations/two run rounds are updated in§0. |

历史配置/SDK/access检查不自动关闭I2/I6/I7，也不阻止如实发布已执行的原生报告；完整成功结论只能给取得完整phase证据的选定case。
Historical configuration/SDK/access checks do not automatically close I2/I6/I7 or prevent honest reporting of executed native runs; full success applies only to selected cases with complete phase evidence.

<a id="7-official-references-checked-on-2026-11-22"></a>
## 8. 官方参考 / Official References

保留原2026-11-22参考复核日期；后续原生执行/配置证据日期在§0/报告。本文仅语言与计划整理，未重新联网核验产品支持，实施前按实际region/API/schema刷新。
Retain the original reference review date of 2026-11-22; later configuration/native evidence dates are in §0/report. This is a language/plan edit, not fresh online product verification; refresh actual regional/API/schema support before implementation.

- [Workspace 支持资源与Action语义 / Supported resources and Action semantics](https://learn.microsoft.com/en-us/azure/chaos-studio/chaos-studio-workspaces-supported-resources)
- [AKS extension preview 前置、验证配置与限制 / Requirements, validated configurations and limitations](https://learn.microsoft.com/en-us/azure/chaos-studio/chaos-studio-aks-extension-overview)
- [AKS 安装归属、namespace、externalResource与参数 / Ownership, namespaces, external binding and parameters](https://learn.microsoft.com/en-us/azure/chaos-studio/chaos-studio-aks-extension-install)
- [资源targeting与Configuration验证 / Resource targeting and configuration validation](https://learn.microsoft.com/en-us/azure/chaos-studio/chaos-studio-workspaces-resource-targeting)
