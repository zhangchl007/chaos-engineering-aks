# Azure Chaos Studio 统一测试用例与覆盖规范 / Unified Test Cases and Coverage Standard

**复核日期 / Reviewed：** 2026-11-23。

**阅读规则：** 中文为场景、范围和结果的主线；英文紧随对应中文，同一行或同一段表达同一要求。产品名、Case ID、Action ID、API 参数和状态枚举保留原文，不另行翻译或改写。英文原有的补充场景全部保留，并补齐中文。
**Reading rule:** Chinese leads the scenarios, scope and results; the corresponding English follows in the same row or paragraph. Product names, Case IDs, Action IDs, API parameters and status enums remain unchanged. All additional scenarios from the former English catalog are retained with Chinese counterparts.

**状态：** 本文是唯一用例清单，不是运行授权。共 **70 个规范用例**：保留原 43 个编号，补充 27 个独立故障边界/验收目标；用户提供的 **39 个中文场景**全部映射。实际执行了其中 9 个用例，两轮合计 18 个成功原生运行；完整基础设施与业务韧性尚未验收。
**Status:** This is the single case catalog, not execution authorization. It contains **70 cases**: 43 original IDs and 27 additional distinct fault boundaries or acceptance objectives. All **39 supplied Chinese scenarios** are mapped. Nine distinct cases have been executed, totaling 18 successful native runs across two rounds; full infrastructure and business resilience remain unverified.

**范围：** 指定非生产资源组内的 VM、AKS、MySQL、PostgreSQL、两种 Redis、Blob Storage、Service Bus、Event Hubs；AKS 托管节点资源组是唯一已规划例外。Cosmos DB、RocketMQ 业务本轮不选；Load Balancer / Application Gateway 为未来补充。
**Scope:** VM, AKS, MySQL, PostgreSQL, both Redis products, Blob Storage, Service Bus and Event Hubs in the designated non-production resource group. The AKS-managed node resource group is the sole planned exception. Cosmos DB and RocketMQ business validation are unselected; Load Balancer / Application Gateway are future coverage.

[实施计划 / Implementation plan](./chaos-studio-implementation-plan.md)只跟踪工程批次；[操作手册 / Operations runbook](./terraform-deployment-runbook.md#chaos-test-operations)保存部署、运行、停止恢复和报告步骤；[原生测试报告 / Native test report](./chaos-studio-native-test-report.md)保存实际执行证据。用例定义与验收以本文为准，不新增第二份清单。
The implementation plan tracks engineering batches only; the runbook owns deployment, execution, stopping, restoration and reporting procedures; the native report records actual execution evidence. This document remains authoritative for case definitions and acceptance.

## 导航 / Navigation

- [0. 当前范围、中文场景映射与实际结果 / Scope, Chinese scenario mapping and actual results](#0-unified-case-standard-and-current-campaign)
- [1. 故障机制与边界 / Mechanisms and boundaries](#1-recommendation-and-boundaries)
- [2. 现有覆盖与资源归属 / Existing coverage and ownership](#2-current-coverage-evidence-and-ownership)
- [3. 分阶段验收与度量 / Phase-specific acceptance and measurement](#3-workload-and-measurement-design)
- [4. 通用客户端补充场景 / Common client-path additions](#4-common-client-path-cases)
- [5. 中文主线及保留的服务场景 / Chinese-led and retained service cases](#5-service-specific-test-cases)
- [6. 后续业务组合验证 / Later business-flow validation](#6-end-to-end-extension-after-individual-services-pass)
- [7. 授权、执行、停止与恢复 / Authorization, execution, stopping and restoration](#7-safety-permissions-stopping-and-restoration)
- [8. 实施任务与执行批次 / Implementation tasks and execution waves](#8-dependency-ordered-delivery-and-execution-waves)
- [9. 证据与结果 / Evidence and verdicts](#9-evidence-and-result-classification)
- [10. 完成检查 / Completion checklist](#10-decisions-and-completion-checklist)

<a id="0-unified-case-standard-and-current-campaign"></a>
## 0. 当前统一范围与执行状态 / Current Scope and Execution Status

<a id="01-本轮范围与状态"></a>
### 0.1 本轮范围与状态 / Campaign scope and status

| 对象 / Area | 中文范围与限制 | Corresponding English scope and limits |
| --- | --- | --- |
| VM | V-03–V-10 为基础设施候选，可规划复用 RocketMQ VM；先核对所有服务、消费者、中断许可、备份及恢复。jumpserver/恢复 VM 永久排除；不默认停止或删除 broker。 | V-03–V-10 are infrastructure candidates; the RocketMQ VM may be reused only after checking every service, consumer, interruption approval, backup and recovery. Jump/recovery VMs are excluded; broker stopping/deletion is not implicit. |
| AKS | K-01–K-06、N-02–N-07 为候选。精确 namespace AND labels、User pool/实例；排除 System pool、控制与恢复组件。N-01 整个 zone 范围另审。 | K-01–K-06 and N-02–N-07 are candidates with exact namespace AND labels and User-pool/instance targeting. Exclude System, control and recovery components. N-01 zone-wide scope requires separate review. |
| PaaS | C-family 按产品/协议拆变体；MySQL、PostgreSQL、两种 Redis、Blob、Service Bus、Event Hubs 按 §0.5 核对资格。选中不等于可执行。 | Split C-family variants by product/protocol; qualify MySQL, PostgreSQL, both Redis products, Blob, Service Bus and Event Hubs under §0.5. Selection is not readiness. |
| 独立专项 / Separate drills | PITR、geo/topology、区域切换、zone-loss 保留，但扩大目标、数据风险或资源生命周期时另行授权。 | Retain PITR, geo/topology, regional promotion and zone-loss drills; expanded targets, data risk or lifecycle changes require separate authorization. |
| 后续/未选 / Later/unselected | D-01/D-02、V-01/V-02 本轮不选；E-01–E-03 与全部业务 SLO 后续验收；L/G 共六项为 Future。I-01 机制/mesh 目标待核验。 | D-01/D-02 and V-01/V-02 are unselected; E-01–E-03 and business SLOs are deferred; all six L/G cases are Future. I-01 mechanism/mesh targets await verification. |
| 私有边界 / Private boundary | 真实订阅、tenant、资源组、端点、VM/VMSS/node IDs、消息实体名只保存私有；每次重查资源组及唯一节点组例外。 | Keep real subscription, tenant, resource group, endpoints, VM/VMSS/node IDs and entity names private; recheck the resource-group boundary and sole node-group exception before every run. |

**准备、能力、授权、执行与验收分开记录。** `Candidate` 为待资格确认，`Future` 为未来范围，`Unselected` 为本轮不选，`Deferred` 为后续阶段。未运行记 `execution=NotRun`；不能将待办、未选或原生配置成功写成 Passed。
**Record preparation, capability, authorization, execution and acceptance separately.** `Candidate` awaits qualification, `Future` is future scope, `Unselected` is outside this campaign, and `Deferred` belongs to a later phase. Unexecuted cases use `execution=NotRun`; pending work, unselected cases and configuration success are not Passed.

| 准备状态 / Preparation status | 中文判定 | Corresponding English meaning |
| --- | --- | --- |
| PendingConfiguration | 能力存在，明确目标配置尚未创建。 | Capability exists; explicit target configuration is missing. |
| AwaitingTarget | 尚未选定符合实体、namespace/labels 或实例边界的目标。 | A qualifying entity, namespace/labels or instance target has not been selected. |
| PendingPrerequisite | 身份、权限、安装、保护或恢复前置待补；记录 owning state。 | Identity, permissions, installation, protection or recovery prerequisites are missing; record the owning state. |
| PendingVerification | 支持、连接、真实匹配、容量或恢复证据待核验；不等于证实不支持。 | Support, connectivity, actual matching, capacity or recovery evidence is unverified; this does not prove incompatibility. |
| PendingDesign | 精确故障语义或作用边界尚未映射，不用不同故障替代。 | Exact fault semantics or targeting boundaries are unmapped; do not substitute another fault. |
| PendingValidation | 配置已部署，但原生 Validate 未通过或错误待定位。 | Configuration is deployed but native Validate has not passed or errors remain. |
| Validated | 最新 Validate 为 `Succeeded` 且解析到明确目标；运行前仍重查动态安全边界与授权。 | Latest Validate is `Succeeded` with explicit resolved targets; dynamic safety and authorization still need pre-run checks. |
| AwaitingAuthorization | 执行、破坏性影响、范围扩大或恢复生命周期待授权。 | Execution, destructive impact, expanded scope or recovery lifecycle awaits approval. |
| Blocked | 实际 SKU/拓扑或复现的未解决前置失败已有具体不兼容证据，只阻塞对应变体。 | Evidenced SKU/topology incompatibility or reproduced unresolved preflight failure blocks only the affected variant. |

原生能力另记“已确认 / 当前未映射 / 当前目标不兼容”；一个用例可有多个准备缺项。本表不修改完整 infra/business runner 的拒绝逻辑、安全门槛或结果枚举。
Track native capability separately as confirmed / currently unmapped / incompatible with the current target. A case may have several missing prerequisites. This table does not change the full infra/business runner's rejection logic, safety gates or result enums.

### 0.2 每个用例的记录模板 / Per-case record

| 字段 / Field | 中文要求 | Corresponding English requirement |
| --- | --- | --- |
| ID / variant / phase | 稳定编号；按产品、协议、planned/forced、topic/subscription 等拆变体；`infra` / `business` 单独结论。原生层单独记录。 | Stable ID; separate product, protocol, planned/forced and topic/subscription variants. Verdicts are separate for `infra` and `business`; native results are another evidence layer. |
| 假设 / Hypothesis | 预期受损对象、真实影响、技术/业务行为与恢复目标可观测、可判定。 | Intended impairment, actual impact, technical/business behavior and recovery objective must be observable and decidable. |
| 前置 / Prerequisites | 当前 region/SKU/HA/agent/extension、健康、身份、消费者、保护、容量、预算及停止恢复权限。 | Current region/SKU/HA/agent/extension, health, identities, consumers, protection, capacity, budgets and stop/recovery rights. |
| 机制 / Mechanism | 原生 service-direct、extension、agent、客户端模拟或服务恢复专项；完整 Action/API/version/schema，不猜 ID、不自动回退 classic。 | Native service-direct, extension, agent, client simulation or service recovery drill; verified Action/API/version/schema, with no guessed IDs or automatic classic fallback. |
| 范围 / Scope | 精确资源/实体/实例/namespace AND labels、实际匹配数、排除项、强度、duration 与硬截止；禁止空/wildcard。 | Exact resource/entity/instance/namespace AND labels, actual match count, exclusions, intensity, duration and hard deadline; no empty/wildcard targeting. |
| 验收 / Acceptance | 基线→注入→实际影响→停止→逐窗口恢复；独立证据、数据核对、限制与结果。Action duration 不等于 outage/RTO。 | Baseline→injection→actual impact→stop→windowed recovery, with independent evidence, reconciliation, limitations and verdicts. Action duration is not outage/RTO. |

### 0.3 分阶段技术与 HA 前置 / Technical and HA prerequisites by phase

本轮先原生运行，不为此新建 canary、observer Job、SDK 流量、proxy 或账本。下表用于后续完整 `phase=infra`；真实订单、库存、cache-aside/outbox 与业务 SLO 属于 `phase=business`。技术探针不是实际应用流量，原生 `Succeeded` 不等于任一完整阶段 Passed。
The current native-first phase does not require new canaries, observer Jobs, SDK traffic, proxies or ledgers. The following table governs later full `phase=infra`; real orders, inventory, cache-aside/outbox and business SLOs belong to `phase=business`. Technical probes are not real application traffic, and native `Succeeded` does not pass either full phase.

| 对象 / Target | 中文技术证据 | Corresponding English technical evidence |
| --- | --- | --- |
| VM | Azure/guest health、CPU/memory/disk/IO、精确进程、实际协议连接；注入达标、非目标/恢复健康、无残留。Running 不替代 guest readiness。 | Azure/guest health, CPU/memory/disk/IO, exact process and real protocol connectivity; achieved effect, healthy non-target/recovery paths and no residue. Running is not guest readiness. |
| AKS | 原/新 Pod UID、node/instance、Ready/events/lease、requests/limits、实际副本/zone/存储放置及剩余容量；不只看新 Pod 存在。 | Original/replacement Pod UIDs, node/instance, Ready/events/leases, requests/limits, actual replica/zone/storage placement and spare capacity; replacement existence alone is insufficient. |
| MySQL / PostgreSQL | 有限唯一 ID 事务写读、attempt/ack/unknown、已确认数据、连接和 HA/角色恢复；未知 commit 先查后判。 | Finite unique-ID transactions, attempt/ack/unknown reconciliation, acknowledged data, connections and HA/role recovery; reconcile unknown commits before deciding. |
| 两种 Redis / Both Redis products | 独立 keys 的读写/版本、连接/拓扑/副本；flush 仅独占可重建库并核对全部 geo links，不承诺缓存写入零丢失。 | Isolated key reads/writes/versions, connectivity/topology/replicas; flush only exclusive reconstructible databases after checking every geo link. No universal zero-loss cache-write guarantee. |
| Blob | operation ID、hash、length、ETag/version、ack/unknown、保护恢复；测试 prefix 与 backend/evidence/backup 分离。 | Operation IDs, hashes, lengths, ETags/versions, ack/unknown and protection/restoration; isolate test prefixes from backend/evidence/backup storage. |
| Service Bus | 专用 queue/topic/subscription、有限 publish/PeekLock/settlement、ack/unknown、唯一技术 effect、outstanding/DLQ；恢复原状态。 | Dedicated queue/topic/subscription, finite publishing/PeekLock/settlement, ack/unknown, unique technical effects and outstanding/DLQ reconciliation; restore prior state. |
| Event Hubs | 专用 hub/group、partition/sequence/offset、ack/unknown、独立 durable checkpoint、lag/retention/replay；不承诺全局顺序、exactly-once 或平台 DLQ。 | Dedicated hub/group, partition/sequence/offset, ack/unknown, independent durable checkpoints and lag/retention/replay; no global ordering, exactly-once or platform DLQ guarantee. |

HA/控制资源是原 owning state 的独立前置变更：审 SKU/region、保护、成本和 delete/replace/migration，不全量重建、不改 backend、不重复管理。ZRS 不等于 GRS/GZRS，Geo-DR 不等于 Geo-Replication，HA standby 不等于独立控制依赖。客户端局部故障可共享未被操作的服务，但必须证明 control path 不受影响；实例级故障须独立依赖与恢复路径。同一服务中的另一实体不能证明实例级隔离，现有 runner 更严格门槛保持不变。
HA/control resources are separately reviewed prerequisites in their original owning state: assess SKU/region, protection, cost and delete/replace/migration risks without full recreation, backend changes or duplicate ownership. ZRS is not GRS/GZRS, Geo-DR is not Geo-Replication, and an HA standby is not an independent control dependency. Client-local faults may share an untouched service only with proven unaffected control access; instance-wide faults require independent dependencies and recovery paths. Another entity in the same service does not prove instance containment; stricter existing runner gates remain unchanged.

### 0.4 用户 39 个中文场景与规范映射 / Mapping of all 39 supplied Chinese scenarios

每个原场景一行；同一行的多个编号/变体分别运行和验收，不代表组合故障。原英文清单额外覆盖的 PostgreSQL、Managed Redis、Service Bus、PITR、客户端与业务场景继续保留在 §4–§6。
Each supplied scenario has one row. Multiple IDs/variants in a row require separate runs and acceptance, not a combined fault. Additional PostgreSQL, Managed Redis, Service Bus, PITR, client and business cases from the former English catalog remain in §4–§6.

| 原编号 / Source | 中文场景 | Corresponding English scenario | Case ID |
| --- | --- | --- | --- |
| 4.1.1 | VM CPU 满载 | VM CPU saturation | V-03 |
| 4.1.2 | VM 内存满载 | VM memory saturation | V-04 |
| 4.1.3 | VM 网络延时 | VM network latency | V-05 |
| 4.1.4 | VM 网络丢包 | VM packet loss | V-06 |
| 4.1.5 | VM 磁盘满载 | VM disk exhaustion | V-07 |
| 4.1.6 | VM 磁盘 IO 压力 | VM disk IO pressure | V-08 |
| 4.1.7 | VM 重启 | VM restart | V-09；不替代 / not V-01 |
| 4.1.8 | VM 应用进程终止 | VM application process termination | V-10 |
| 4.2.1 | AKS Pod 意外终止 | AKS Pod termination | K-01 |
| 4.2.2 | AKS Pod CPU 满载 | AKS Pod CPU saturation | K-02 |
| 4.2.3 | AKS Pod 内存泄漏 | AKS Pod memory leak | K-03 固定压力 / fixed pressure；K-06 逐步增长 / progressive growth |
| 4.2.4 | AKS Pod 网络丢包 | AKS Pod packet loss | K-05 |
| 4.2.5 | AKS Pod 网络延时 | AKS Pod network latency | K-04 |
| 4.2.6 | AKS 节点 CPU 满载 | AKS node CPU saturation | N-02 |
| 4.2.7 | AKS 节点内存满载 | AKS node memory saturation | N-03 |
| 4.2.8 | AKS 节点网络丢包 | AKS node packet loss | N-04 |
| 4.2.9 | AKS 节点网络延时 | AKS node network latency | N-05 |
| 4.2.10 | ASM 控制层/数据层断连 | ASM control/data-plane disconnection | I-01 |
| 4.2.11 | AKS API Server/节点断连 | AKS API Server/node partition | N-06 |
| 4.3.1 | MySQL HA 故障转移 | MySQL HA failover | M-01 |
| 4.3.2 | MySQL 重启 | MySQL restart | M-02 |
| 4.3.3 | MySQL 网络中断 | MySQL connection blackout | C-01.mysql |
| 4.3.4 | MySQL 只读副本不可用 | MySQL read-replica unavailability | M-04 |
| 4.4.1 | Storage 网络不可达 | Storage connection/DNS failure | C-01.blob / C-04.blob |
| 4.4.2 | Blob 误删与恢复 | Blob accidental deletion and recovery | S-04 |
| 4.4.3 | Storage 区域故障转移 | Storage planned regional failover | S-03；不是实际区域中断 / not an actual region outage |
| 4.5.1 | Legacy Redis 网络不可达 | Legacy Redis connection/DNS failure | C-01.legacy-redis / C-04.legacy-redis |
| 4.5.2 | Legacy Redis 主节点重启/倒换 | Legacy Redis primary reboot/transition | R-01 |
| 4.5.3 | Legacy Redis 副本重启 | Legacy Redis replica reboot | R-02 |
| 4.5.4 | Legacy Redis 全数据库清空 | Legacy Redis full database flush | R-04；不替代 / not R-03 |
| 4.6.1 | Event Hubs 网络不可达 | Event Hubs connection/DNS failure | C-01.event-hubs / C-04.event-hubs；不替代 / not H-01/H-02 |
| 4.6.2 | Event Hubs 消费积压 | Event Hubs consumer backlog | H-04 |
| 4.6.3 | Event Hubs 跨区域倒换 | Event Hubs cross-region promotion | H-05 元数据 / metadata；H-06 数据复制 / data replication |
| 4.7.1 | LB 单后端故障 | LB single-backend failure | L-01 / Future |
| 4.7.2 | LB 后端网络中断 | LB backend network interruption | L-02 / Future |
| 4.7.3 | LB 后端探针异常 | LB backend probe failure | L-03 / Future |
| 4.8.1 | Application Gateway 单后端故障 | Application Gateway single-backend failure | G-01 / Future |
| 4.8.2 | Application Gateway 后端网络中断 | Application Gateway backend network interruption | G-02 / Future |
| 4.8.3 | Application Gateway 后端探针异常 | Application Gateway backend probe failure | G-03 / Future |

额外 N-07 是单测试节点不可用；N-01 是获批 zone 范围不可用，两者不能互相验收。满载/泄漏是原始场景名称，不授权直接 100% 压力或无限增长。
Additional N-07 covers one unavailable test node; N-01 covers the approved zone scope. Neither passes the other. Saturation/leak are supplied scenario names, not authorization for immediate 100% pressure or unbounded growth.

<a id="05-原生能力优先本轮执行与暂缓标注"></a>
### 0.5 原生优先：实际结果与全部用例状态 / Native-first results and status of all cases

**最新实际证据：** 2026-11-23 首轮 10:16:27–10:50:48，项目代码重跑 11:24:31–11:55:14（UTC+08:00）。两轮各执行同样 9 项：每轮 9 个 run / Action 为 `Succeeded`，7 项管理面影响/恢复 Passed，Redis 两项 Inconclusive；完整 infra/business 均 Inconclusive（未验证）。两轮共18次运行，仍为9个不同用例。
**Latest recorded evidence:** First round 10:16:27–10:50:48 and project-code rerun 11:24:31–11:55:14 on 2026-11-23 (UTC+08:00). Each round executed the same nine cases: nine `Succeeded` runs/Actions, seven management-plane impact/recovery Passed and two Redis Inconclusive. Full infra/business verdicts remain Inconclusive (unverified). Eighteen runs cover nine distinct cases.

| Case ID | 中文实际结果 | Corresponding English actual result |
| --- | --- | --- |
| B-01 / B-02 | queue 分别 Active→SendDisabled/ReceiveDisabled→Active；原生成功，管理面恢复 Passed；消息/业务完整性未验证。 | Queue Active→SendDisabled/ReceiveDisabled→Active in separate runs; native success and management recovery Passed; message/business integrity unverified. |
| H-01 / H-02 | hub 分别 Active→SendDisabled/Disabled→Active；原生成功，管理面恢复 Passed；checkpoint/replay 未验证。 | Hub Active→SendDisabled/Disabled→Active in separate runs; native success and management recovery Passed; checkpoint/replay unverified. |
| M-01 / M-02 | HA 切换/重启真实执行；最终 Ready、HA Healthy、Resource Health Available，管理面 Passed；事务和 RPO 未验证。首轮查询超时断档保留。 | HA failover/restart executed; final Ready, HA Healthy and Resource Health Available, management plane Passed; transactions/RPO unverified. Preserve the first-round query-timeout observation gap. |
| P-01 | planned failover 原生成功、管理面恢复 Passed。首轮 Unavailable、重跑 Degraded 后均复核到 Available；使用同一 run 恢复观察，无重复 Execute。 | Planned failover succeeded natively and management recovery Passed. First-round Unavailable and rerun Degraded were rechecked to Available; observation resumed on the same run without duplicate Execute. |
| R-01 / R-02 | 原生重启成功，但缺独立节点/连接/副本重新加入证据，实际影响 Inconclusive；不能把约8–10秒 run 时长当重启/outage。 | Native reboots succeeded, but independent node/connectivity/replica-rejoin evidence is missing, so impact is Inconclusive; approximately 8–10-second run durations are not reboot/outage durations. |

收尾五个 PaaS 目标 Available、数据库 Ready/HA Healthy、queue/hub Active、无活动运行；private AKS 不变。重跑 Activity Log 含 queue write 4、hub write 4、MySQL restart 1、MySQL failover 1、PostgreSQL restart 1（planned failover 下层操作）、Redis forceReboot 2；审计不替代协议/数据证据。Chaos owning state 完整输入 replan exit code 0，仅证明该配置栈无漂移。详见原生报告 §1–§8。
Final checks recorded all five PaaS targets Available, databases Ready/HA Healthy, queue/hub Active and no active runs; private AKS remained unchanged. Rerun Activity Log recorded four queue writes, four hub writes, one MySQL restart, one MySQL failover, one PostgreSQL restart (underlying planned-failover operation) and two Redis forceReboots; audit is not protocol/data evidence. Full-input Chaos-state replan exit code 0 proves only that configuration stack has no drift. See native report §1–§8.

下表覆盖全部70个编号，是能力/准备状态，不是全矩阵通过结论；未列在上述实际执行表的61项均 `execution=NotRun`。
The following table covers all 70 IDs as capability/preparation status, not matrix acceptance; the remaining 61 cases outside the executed table are `execution=NotRun`.

| Case ID | 中文能力与本轮状态 | Corresponding English capability and campaign status |
| --- | --- | --- |
| M-01, M-02, P-01, R-01, R-02, B-01, B-02, H-01, H-02 | 已确认原生能力、明确单目标/单消息实体，实际结果见上表。 | Confirmed native capability with explicit single targets/entities; actual results above. |
| P-02 | forced failover 已配置/Validated；执行仍 AwaitingAuthorization。SameZone HA 不证明 zone-loss。 | Forced failover configured/Validated; execution AwaitingAuthorization. SameZone HA does not prove zone-loss resilience. |
| B-03 | 原生 topic/subscription state 存在；AwaitingTarget / PendingConfiguration，Discrete 恢复与 opt-in 待审；queue 结果不替代。 | Native topic/subscription state exists; AwaitingTarget / PendingConfiguration, with Discrete restoration and opt-in review pending; queue results do not substitute. |
| V-09 | 单 VM restart 已 Validated；所有 broker/间接消费者、中断与 guest 恢复仍 PendingVerification，未执行。 | Single-VM restart Validated; broker/indirect consumers, interruption and guest recovery remain PendingVerification; not executed. |
| V-03, V-04 | 原生 VM 压力存在；Ubuntu 22.04 合格，VM managed identity 缺失，public outbound/headroom/恢复待核验。原生运行自动安装并保留 agent，不需手工预装 classic agent。 | Native VM pressure exists; Ubuntu 22.04 qualifies, VM managed identity is missing and public outbound/headroom/recovery are unverified. Native execution installs and retains the agent; manual classic-agent preinstallation is unnecessary. |
| K-01–K-05 | extension 能力存在、版本0.1.12已安装；AwaitingTarget / PendingVerification。当前 private API 观察路径不可用；官方 private-cluster preview 未验证，不是永久不支持。 | Extension capability exists and version 0.1.12 is installed; AwaitingTarget / PendingVerification. Current private-API observation access is unavailable; officially unvalidated private-cluster preview is not permanent incompatibility. |
| N-01 | 原生 VMSS shutdown 存在；zone-wide 配置/执行 PendingConfiguration / AwaitingAuthorization；不能借 N-07 授权扩大范围。 | Native VMSS shutdown exists; zone-wide preparation/execution PendingConfiguration / AwaitingAuthorization; N-07 approval does not expand scope. |
| N-07 | 配置 Validate 成功，User VMSS zone 2 当前匹配一实例；实际故障 PendingVerification / NotRun。User/System 各两节点分布 zone 2、3；单 User 节点损失一半容量，workload/存储/剩余容量未核验。 | Configuration Validate passed; User VMSS zone 2 currently matches one instance. Fault execution PendingVerification / NotRun. User/System each have two nodes in zones 2/3; losing one User node removes half its capacity, while workload/storage/spare-capacity evidence is missing. |
| N-02, N-03 | catalog 有 VMSS 压力；模块仅实现单 VM，精确实例/agent/出站/容量 PendingDesign / PendingVerification，不压整池。 | Catalog includes VMSS pressure; module implements single-VM pressure only. Exact instance/agent/outbound/capacity PendingDesign / PendingVerification; no pool-wide pressure. |
| S-03 | Blocked：当前 Standard_ZRS 无 geo planned failover 前置，不为补覆盖迁移 GRS/GZRS。 | Blocked: current Standard_ZRS lacks geo planned-failover prerequisites; do not migrate to GRS/GZRS merely for coverage. |
| A-02 | 原生 flush 存在；独占/可重建与删除恢复 PendingVerification / AwaitingAuthorization，不默认清库。 | Native flush exists; exclusivity/reconstructibility and deletion/recovery PendingVerification / AwaitingAuthorization; no default flush. |
| A-04 | Blocked：实际没有 geo links，无可 unlink 对象；不自动新增伙伴。 | Blocked: no actual geo links to unlink; do not automatically add a partner. |
| C-01–C-05 | 单依赖连接、延迟、未知确认、DNS、协议限流尚未确认等价原生 Action；本轮不建 proxy/hook。 | No equivalent native Actions confirmed for single-dependency connectivity, latency, unknown acknowledgment, DNS or protocol throttling; no proxies/hooks in this phase. |
| M-04 | 独立 replica 目标与等价原生 Action 未确认；HA standby 不替代。 | Independent replica target and equivalent native Action unconfirmed; HA standby is not a substitute. |
| R-03, R-04 | Legacy Redis 有限 key/全库 flush 尚未确认 Workspace Action；服务数据面操作另审，不套 Managed Redis。 | No Workspace Action confirmed for Legacy Redis bounded-key/full-database flush; data-plane drills require separate review, not Managed Redis Actions. |
| A-01, A-03, S-01, S-02 | 客户端断连/区域重定向、Blob 传输/secondary-read 未确认等价原生 Action；当前 ZRS 也无 secondary-read 前置。 | No equivalent native Actions confirmed for client disconnect/regional redirection or Blob transfer/secondary reads; current ZRS also lacks secondary-read prerequisites. |
| B-04, H-03, H-04 | commit/settlement/checkpoint 时序或 consumer pause 未确认等价原生机制，状态禁用不能替代。 | Equivalent native commit/settlement/checkpoint timing or consumer-pause mechanisms are unconfirmed; entity disable is not a substitute. |
| K-06 | 逐步增长泄漏模型未映射；固定 K-03 不等价，不编写模拟补本轮。 | Progressive memory-leak model is unmapped; fixed K-03 is not equivalent, and no simulation is added for this phase. |
| V-05, V-06, V-07, V-08, V-10 | 精确 VM 路径/卷/进程原生机制未确认；不回退 classic 或安装 guest 模拟。 | Exact VM path/volume/process native mechanisms unconfirmed; no classic fallback or guest simulations. |
| N-04, N-05, N-06, I-01 | 精确 node 网络/API partition、ASM control/data partition 未映射；PendingDesign，mesh 目标 AwaitingTarget。不改共享路由/NSG、不安装 mesh。 | Exact node network/API partition and ASM control/data partition unmapped; PendingDesign, with mesh AwaitingTarget. No shared route/NSG changes or mesh installation. |
| M-03, P-03, S-04, B-05, H-05, H-06 | 服务 PITR/保护/geo 专项 Deferred，独立恢复、数据与生命周期授权待完成，不算本轮 Chaos 原生通过。 | Service PITR/protection/geo drills Deferred; separate recovery/data/lifecycle approval pending, not native Chaos passes in this campaign. |
| D-01, D-02, V-01, V-02 | Unselected：Cosmos / RocketMQ 业务；已知故障机制不自动证明业务 durability。 | Unselected: Cosmos / RocketMQ business cases; known fault mechanisms do not establish business durability. |
| L-01–L-03, G-01–G-03 | Future：无获授权目标；LB admin-state catalog 不覆盖所有 network/probe/Gateway 语义。 | Future: no approved targets; LB admin-state catalog does not cover every network/probe/Gateway semantic. |
| E-01–E-03 | Deferred：实际业务流/SLO/不变量后续接入，不作为原生运行的新前置。 | Deferred: real business flows/SLOs/invariants come later, not new native-execution prerequisites. |

**AKS 当前限制：** 操作端无法解析 private API，其既有 private endpoint TCP 路径亦不可达；近10分钟精确 cluster 的 KubeNodeInventory/KubePodInventory 返回0行，不能据此断言无 workload 或节点 Ready。先由已有获批私网执行端取得实际放置与恢复证据；本次不开放公网、不启用 Run Command、不新增临时身份或权限绕过。
**Current AKS limitation:** The operator cannot resolve the private API, and its existing private-endpoint TCP path is also unreachable. Exact-cluster KubeNodeInventory/KubePodInventory queries returned zero rows over ten minutes; this proves neither absence of workloads nor Ready nodes. Obtain actual placement/recovery evidence through an existing approved private execution host; do not open public access, enable Run Command or add temporary identities/permissions to bypass the boundary.

### 0.6 配置历史与最短原生流程 / Configuration history and minimal native workflow

历史配置证据：25个推荐 Scenarios、初次发现0/检查模板 Configuration 0；显式 discover 后57资源，首批10个单 Action/明确目标配置，两批各16 create、已有目标 update/delete/replace 0。后续添加 P-02/N-07，共7 create、11 metadata update、0 delete/replace；发现69资源、12配置、7明确目标，12/12 Validate Succeeded，完整输入 replan 0。发现数不是授权数。六个初始 target-only custom roles 后补 User VMSS role；节点组 Reader 传播经有限重验，无扩大权限。
Historical configuration evidence: 25 recommended Scenarios, initially zero discovered resources and zero Configurations in the inspected template; explicit discovery found 57 resources. Initial ten single-Action/explicit-target configurations were deployed in two batches of 16 creates, with zero existing-target updates/deletes/replacements. Adding P-02/N-07 required seven creates, 11 metadata updates and zero deletes/replacements; discovery reached 69 resources, 12 configurations and seven explicit targets, with 12/12 Validate Succeeded and full-input replan 0. Discovery count is not authorization count. Six initial target-only custom roles were followed by a User VMSS role; node-group Reader propagation was finitely revalidated without broader rights.

初始配置名为 `m01-mysql-ha-failover`、`m02-mysql-restart`、`p01-postgresql-planned-failover`、`r01-legacy-redis-primary-reboot`、`r02-legacy-redis-secondary-reboot`、`b01-servicebus-send-disabled`、`b02-servicebus-receive-disabled`、`h01-eventhub-send-disabled`、`h02-eventhub-disabled`、`v09-private-vm-restart`；后补 `p02-postgresql-forced-failover`、`n07-single-user-node-shutdown`，Configuration 为 `approved-targets`。推荐库保留，不整套执行含 Load Testing/VMSS/数据库/runbook 的多 Action 模板。
Initial configuration names are listed above; later additions are `p02-postgresql-forced-failover` and `n07-single-user-node-shutdown`, using Configuration `approved-targets`. Retain the recommendation library; do not execute whole multi-Action templates containing Load Testing/VMSS/databases/runbooks.

| 步骤 / Step | 中文操作边界 | Corresponding English operational boundary |
| --- | --- | --- |
| 1 | 选已有 Workspace 单 Action Configuration，不用 classic Targets/capabilities；重查健康、目标、影响、权限与恢复。 | Select an existing Workspace single-Action Configuration, not classic Targets/capabilities; recheck health, targets, impact, permissions and recovery. |
| 2 | 原生 Validate 必须最新 Succeeded 且解析到获批目标；动态实例/Pod 另核验。RequiresAttention 对照真实角色后有限重试，不自动 fixResourcePermissions。 | Latest native Validate must be Succeeded with approved resolved targets; dynamically verify instances/Pods separately. Investigate RequiresAttention against actual roles and retry finitely, never auto-fixResourcePermissions. |
| 3 | 仅获明确授权的 operator/助手 Execute，串行；本轮已执行 Action duration 1分钟，不等于 outage。运行15分钟或恢复10分钟超限、越界即停。 | Only an explicitly authorized operator/assistant Executes, serially. Executed Actions used one-minute duration, not outage length. Stop on target escape, a 15-minute run limit or a ten-minute recovery limit. |
| 4 | 用原生 report、Activity Log、既有 Monitor/events 观察；Cancelable 先取消再按原状态恢复本次实体，Discrete 不可撤销；不盲重发 Execute/failover。 | Observe native reports, Activity Log and existing Monitor/events; cancel Cancelable runs then restore only affected entities to prior state. Discrete actions are not undoable; never blindly resend Execute/failover. |
| 5 | 确认真实作用、恢复、无残留，再下一故障；原生结果、影响/恢复、完整 infra/business 分栏。零目标/Skipped 不通过。 | Confirm actual impact, restoration and no residue before the next fault. Separate native, impact/recovery and full infra/business results. Zero-target/Skipped runs do not pass. |

官方 `2026-08-01-preview` 路径：Configuration `POST .../execute`、`POST .../validate` 无 body；run `GET .../runs/{runId}`、`POST .../runs/{runId}/cancel`。仅供显式操作，不创建 Terraform run/provisioner 或猜 `runs/start`。HTTP 200 不等于 Validate 成功，depends_on 不保证 RBAC 已传播。
Verified `2026-08-01-preview` paths: Configuration `POST .../execute` and `POST .../validate` have no body; runs use `GET .../runs/{runId}` and `POST .../runs/{runId}/cancel`. These are explicit operations, not Terraform run/provisioner resources or guessed `runs/start` APIs. HTTP 200 is not Validate success; depends_on does not guarantee RBAC propagation.

<a id="1-recommendation-and-boundaries"></a>
## 1. 故障机制与边界 / Mechanisms and Boundaries

| 机制 / Mechanism | 中文含义 | Corresponding English meaning |
| --- | --- | --- |
| Workspace / Scenario | 当前推荐的新测试模型；service-direct/extension/agent 按 region、schema、资格和身份核验。 | Recommended model for new tests; qualify service-direct/extension/agent Actions by region, schema, eligibility and identity. |
| 客户端模拟 / Client-path simulation | 云端测试 workload 的专用 hook/protocol proxy，只证明客户端韧性，不称 Azure 服务真实停机。 | Dedicated hooks/protocol proxies for cloud test workloads prove client resilience, not actual Azure service outages. |
| 服务专项 / Service-native drill | PITR、保护恢复、区域 promotion 等独立操作，不冒充所选 Chaos Action。 | PITR, protection restoration and regional promotion are separate procedures, not the selected Chaos Action. |

遵循 [Well-Architected 韧性测试 / reliability testing][waf]，明确证据层级。禁止混用 classic URN/targets/capabilities，未支持不自动回退。Workspace 与目标可跨 region，但实际 Action/资源约束须验证。
Follow Well-Architected reliability testing and declare evidence levels. Never mix classic URNs/targets/capabilities or fall back automatically. Workspace and target regions may differ, subject to actual Action/resource constraints.

强制边界：非生产、合成数据、一个目标/依赖的一种故障、无重叠运行；精确 allowlist、namespace/labels/实体/端点与所有间接消费者。canary 只限制流量，不限制 service-direct 影响。禁止共享 DNS/NSG/private endpoint/节点生命周期改动、订阅 Owner/Contributor、默认故障启动和未经授权的部署/扩缩容/flush。不删共享 DNS A record、不撤共享 SAS Listen、不启用 Redis access keys、不批量按名字 kill、不全盘填满、不默认装 Chaos Mesh。
Mandatory boundaries: non-production synthetic data, one fault on one target/dependency, no overlapping runs, and exact allowlists/namespaces/labels/entities/endpoints plus all indirect consumers. Canary selection bounds traffic, not service-direct impact. No shared DNS/NSG/private-endpoint/node-lifecycle changes, subscription Owner/Contributor, default fault starts or unauthorized deployment/scaling/flush. Never delete shared DNS A records, revoke shared SAS Listen, enable Redis access keys, kill by name in bulk, fill whole disks or install Chaos Mesh by default.

<a id="2-current-coverage-evidence-and-ownership"></a>
## 2. 现有覆盖与归属 / Existing Coverage and Ownership

配置声明、安装可用、真实故障影响、完整技术验收、业务验收分层记录。模块、mock、Ready、推荐模板、无漂移 plan 不替代下一层；历史安装/版本/检查不是本次实时重验。
Record declared configuration, usable installation, actual impact, full technical acceptance and business acceptance separately. Modules, mocks, Ready states, recommendations and no-drift plans do not prove subsequent layers; historical installation/version/checks are not fresh verification.

| 现有部分 / Existing area | 中文证据与缺项 | Corresponding English evidence and gaps |
| --- | --- | --- |
| [平台 / Platform](../main.tf)、[fixtures](../fixtures.tf) | 根模块管理 RG/私有 AKS/网络与 PaaS；模块存在不证明已部署/合格。Cosmos dev 不创建账户；RocketMQ Running 不证明 NameServer/Broker/存储与业务就绪。 | Root owns RG/private AKS/network and PaaS fixtures; module presence is not deployment/eligibility. Dev Cosmos creates no account; RocketMQ Running does not prove NameServer/Broker/store/business readiness. |
| [Chaos 模块 / module](../modules/chaos/)、[stack](../stacks/chaos/) | UAMI、RG discovery、target-only 权限、单 Action 配置；默认关闭创建，无 run/schedule。existing-Workspace reference 未实现，不覆盖外部归属资源。 | UAMI, RG discovery, target-only rights and single-Action configurations; creation defaults off, no run/schedule. Existing-Workspace reference is unimplemented; do not overwrite externally owned resources. |
| extension / [Pod 定义 / definitions](../modules/chaos/pods.tf) | 历史 extension 0.1.12、auto-upgrade off、federation/trust/operator grant、Deployments 1/1各两个、DaemonSet 4/4 Ready；五种有界 Action。安装/连接 Pending 不证明私有集群功能合格；当前目标另核验。 | Historical extension 0.1.12, auto-upgrade off, federation/trust/operator grant, two Deployments each 1/1 and DaemonSet 4/4 Ready; five bounded Actions. Installation/connection Pending does not qualify private-cluster functionality; recheck current targets. |
| [验证模块 / Verification module](../modules/chaos-validation/) | opt-in 有限 HTTPS Jobs、streaming evidence、availability evaluator、Blob/SB reference clients、crash-safe ledger、manifest/recovery checks；声明的 Job 仍运行 probe.py。其他协议、真实应用、独立 ledger/完整 observer/通知未完成。 | Opt-in finite HTTPS Jobs, streaming evidence, availability evaluator, Blob/SB reference clients, crash-safe ledger and manifest/recovery checks; declared Job still runs probe.py. Other protocols, real apps, independent ledgers/full observers/notifications remain incomplete. |
| [监控 / Monitoring](../modules/monitoring/)、[tests](../tests/)、[CI](../.github/workflows/terraform-validation.yml) | 已有固定工具静态验证；历史计数不当作新结果，policy applicability 未因整理自动解决。ingress/Argo CD 非 Chaos 必需；ACR/DNS/backend/backup/恢复默认排除。AGFC 不是 LB 目标。 | Fixed-tool static validation exists; historical counts are not fresh results, and policy applicability is not resolved by editing. Ingress/Argo CD are not Chaos prerequisites; ACR/DNS/backend/backup/recovery are excluded. AGFC is not an LB target. |

历史复核工具：CLI 1.15.6（CI/runbook），AzureRM 4.55.0、AzAPI 2.14.0、Random 3.7.2、Kubernetes 2.38.0、Helm 2.17.0；[根约束 / root constraints](../version.tf)为 `>=1.9,<2.0`，不是精确 CLI pin。各 stage lockfile/测试 overrides 保留，不为本次文档升级 Provider/backend。旧“无模块/CI/Workspace”、旧版本/下载失败库存已被后续证据替代；旧环境 RG/网络/身份/命名/接口迁移风险仍须逐 state 审查。历史临时 IAM/guest 工具已清理、VM 原身份恢复；运行前重验，bootstrap checksum 修正不等于版本/state 迁移。
Historically reviewed tools: CLI 1.15.6 (CI/runbook), AzureRM 4.55.0, AzAPI 2.14.0, Random 3.7.2, Kubernetes 2.38.0 and Helm 2.17.0. Root `>=1.9,<2.0` is not an exact CLI pin. Preserve stage lockfiles/test overrides; no Provider/backend upgrades in this documentation change. Older missing-module/CI/Workspace, version and download-failure inventories are superseded; older-environment RG/network/identity/naming/interface migrations still need state-specific review. Historical temporary IAM/guest tools were cleaned up and the original VM identity restored; requalify access. Bootstrap checksum correction is not a version/state migration.

| 归属 / Owner | 中文职责 | Corresponding English responsibility |
| --- | --- | --- |
| Platform state | RG、AKS/VNet/ACR、PaaS/VM、监控；保留接口/address，关闭已启用资源可能删除。 | RG, AKS/VNet/ACR, PaaS/VM and monitoring; preserve interfaces/addresses, as disabling existing components can delete them. |
| Cluster state | 已有私有 AKS 的可选 controller/GitOps、namespace、脚本和获批 Job；建 Job 即运行流量，须授权。 | Optional controllers/GitOps, namespaces, scripts and approved Jobs on existing private AKS; Job creation starts traffic and needs approval. |
| Chaos state | Workspace/UAMI、discovery grants、Action 权限、Scenarios/configurations；只配置不启动。 | Workspace/UAMI, discovery grants, Action rights and Scenarios/configurations; configuration only, no execution. |
| 安装/恢复操作者 / Installer/recovery operator | extension、subscriber/federation/connection/operator grant 外部归属，不重复；恢复/清理独立授权。 | Externally owned extension/subscriber/federation/connection/operator grants are not duplicated; recovery/cleanup requires separate approval. |

环境/stage 使用独立 state/backend key/身份，tfvars/CLI workspace 不是隔离。根默认 local state 须保护并互斥；团队/云端 remote backend 独立引导、Entra认证、锁/备份/网络保护，迁移另审。不故障化 backend/evidence/backup，不用空 state、state rm、force-unlock/destroy 掩盖问题。
Use separate environment/stage state/backend keys and identities; tfvars/CLI workspaces are not isolation. Protect and serialize the root's default local state. Team/cloud remote backends require independent bootstrap, Entra authentication, locking/backups/network protection and separately reviewed migration. Never fault backend/evidence/backup storage or hide problems with empty state, state rm, force-unlock or destroy.

### 2.1 Action 与参数契约 / Action and parameter contract

以下 catalog 标识不等于订阅资格；实施前读取目标 Workspace region 的完整 schema/权限/持续时间，固定 `2026-08-01-preview`，不用猜测字段。
Catalog identifiers are not subscription eligibility. Retrieve full schema/permissions/duration for the Workspace region before implementation, retain `2026-08-01-preview`, and never guess fields.

| 资源 / Resource type | Action ID | 中文语义与关键参数 | Corresponding English semantics and parameters |
| --- | --- | --- | --- |
| MySQL / `Microsoft.DBforMySQL/flexibleServers` | `microsoft-mysql-failover/1.0` | Cancelable；必填 RestoreOnStop；健康 HA，恢复旧主仅尝试不保证。 | Cancelable; required RestoreOnStop, healthy HA; returning to the old primary is an attempt, not guaranteed rollback. |
| MySQL / 同上 / same | `microsoft-mysql-restart/1.0` | Discrete；一次重启，无 undo。 | Discrete; one restart, no undo. |
| PostgreSQL / `Microsoft.DBforPostgreSQL/flexibleServers` | `microsoft-azurepostgresql-failover/1.0` | Cancelable；FailoverMode PlannedFailover/ForcedFailover；可选 RestoreOnStop/SkipIneligibleServers；非HA/replica不合格。 | Cancelable; FailoverMode PlannedFailover/ForcedFailover; optional RestoreOnStop/SkipIneligibleServers; non-HA/replica targets ineligible. |
| Legacy Redis / `Microsoft.Cache/redis` | `microsoft-azureclusteredcacheforredis-reboot/1.0` | Discrete；RebootType PrimaryNode/SecondaryNode/AllNodes；cluster 才用明确 ShardId，不套 Managed Redis。 | Discrete; RebootType PrimaryNode/SecondaryNode/AllNodes; explicit ShardId only for clustered caches, not Managed Redis. |
| Managed Redis / `Microsoft.Cache/redisEnterprise` | `microsoft-managedredis-flushdatabase/1.0` | Discrete；DatabaseName；可能清空全部 geo-linked caches。 | Discrete; DatabaseName; may erase every geo-linked cache. |
| Managed Redis / 同上 / same | `microsoft-managedredis-forceunlink/1.0` | Discrete；DatabaseName/LinkedDatabaseResourceIds；拓扑变化，无自动 re-link。 | Discrete; DatabaseName/LinkedDatabaseResourceIds; topology change, no automatic re-link. |
| Storage / `Microsoft.Storage/storageAccounts` | `microsoft-storageaccount-plannedfailover/1.0` | Discrete；全账户、合格 geo 冗余、初始同步完成、两区可用。 | Discrete; account-wide, eligible geo redundancy, completed initial sync, both regions available. |
| Service Bus / `Microsoft.ServiceBus/namespaces` | `microsoft-servicebus-changequeuestate/1.0` | Cancelable；queues/desiredState：Active/Disabled/SendDisabled/ReceiveDisabled。 | Cancelable; queues/desiredState: Active/Disabled/SendDisabled/ReceiveDisabled. |
| Service Bus / 同上 / same | `microsoft-servicebus-changesubscriptionstate/1.0` | Discrete；topic/subscriptions/desiredState Active或Disabled；显式恢复。 | Discrete; topic/subscriptions/desiredState Active or Disabled; explicit restoration. |
| Service Bus / 同上 / same | `microsoft-servicebus-changetopicstate/1.0` | Discrete；topics/desiredState Active或Disabled；显式恢复。 | Discrete; topics/desiredState Active or Disabled; explicit restoration. |
| Event Hubs / `Microsoft.EventHub/namespaces` | `microsoft-eventhub-changeeventhubstate/1.0` | Cancelable；eventhubs/desiredState Active/Disabled/SendDisabled；无 ReceiveDisabled。 | Cancelable; eventhubs/desiredState Active/Disabled/SendDisabled; no ReceiveDisabled. |
| Cosmos / `Microsoft.DocumentDB/databaseAccounts` | `microsoft-documentdb-offlineregion/1.0` | Cancelable；RegionName 是 display name，核对API/读写拓扑。 | Cancelable; RegionName is a display name; qualify API/read-write topology. |
| VM / `Microsoft.Compute/virtualMachines` | `microsoft-compute-restart/1.0` | Discrete；重启不是 broker 恢复证明。 | Discrete; restart does not prove broker recovery. |
| VMSS / `Microsoft.Compute/virtualMachineScaleSets` | `microsoft-virtualmachinescaleset-shutdown/1.0` | Cancelable；Zones/GracefulShutdown；可能命中 zone 内全部实例。 | Cancelable; Zones/GracefulShutdown; may affect every matching instance in the zone. |
| VM agent；VMSS仅catalog / VM agent; VMSS catalog-only | `microsoft-compute-cpuPressure/1.0` | Continuous；实际区域 pressureLevel 1–100、必填 duration；单合格 VM 默认≤50。 | Continuous; regional pressureLevel 1–100 and required duration; one qualified VM, default ≤50. |
| VM agent；VMSS仅catalog / VM agent; VMSS catalog-only | `microsoft-compute-physicalMemoryPressure/1.0` | Continuous；pressureLevel 1–99、必填 duration；不是逐步泄漏。 | Continuous; pressureLevel 1–99 and required duration; not a progressive leak. |

模块 allowlist 为14个 service-direct + 2个单VM agent压力，不是整个官方 catalog；UK South schema 的 `pressureLevel`/`duration` 大小写保留，不能以 URN 替换 Action ID。compute shutdown/redeploy/delete/hibernate 不等价；未确认 Managed Redis reboot。
The module allowlists 14 service-direct plus two single-VM agent-pressure Actions, not the entire official catalog. Preserve UK South schema casing for `pressureLevel`/`duration`; do not substitute URNs for Action IDs. Compute shutdown/redeploy/delete/hibernate are not interchangeable; no Managed Redis reboot is confirmed.

配置守则：service-direct whole-minute duration 1–5，Discrete 也必填但非 outage/回滚承诺。实体数组 queues/topics/subscriptions/eventhubs/linked IDs 按 schema JSON-array 编码。`resourceTargeting` 不混旧 filters/exclusions：同类别 OR、非空类别间 AND、排除优先，空类别不限制；这不是 Pod labels AND 规则。明确资源ID并每次对比实际解析/排除名单，更新保留完整参数。destructive opt-in 不等于执行许可，代码危险列表非完整风险分类。
Configuration rules: service-direct whole-minute durations 1–5, required even for Discrete Actions but not an outage/rollback promise. Encode entity arrays queues/topics/subscriptions/eventhubs/linked IDs per schema. Use `resourceTargeting`, not mixed old filters/exclusions: OR within a category, AND across nonempty categories, exclusions win, empty categories do not restrict. This differs from Pod-label AND matching. Require exact resource IDs, compare resolved/excluded lists before each run and preserve full parameters on updates. Destructive opt-in is not execution permission, and the code's destructive list is not a complete risk classification.

<a id="3-workload-and-measurement-design"></a>
## 3. 分阶段验收与度量 / Phase-specific Acceptance and Measurement

### 3.1 初始技术与 Pod 参数 / Initial technical and Pod bounds

网络建议 +100ms/1% loss/60秒；Pod guards：≤25%、≤60秒、CPU 1–2 cores、memory 1–128MB（memoryConsumptionMegabytes）、latency 1–500ms、loss 1–10%。先核百分比取整和最小可行效果。VM/node CPU 从50%逐级，95–100%、memory90%、disk exhaustion 仅专用可恢复目标另审，不能为满载名称放宽 guards。
Proposed network start: +100ms/1% loss/60 seconds. Pod guards: ≤25%, ≤60 seconds, CPU 1–2 cores, memory 1–128MB (memoryConsumptionMegabytes), latency 1–500ms and loss 1–10%. Check rounding and minimum practical effects first. VM/node CPU starts at 50%; 95–100% CPU, 90% memory and disk exhaustion require separate review on dedicated recoverable targets. Saturation names do not relax guards.

完整 infra 建议每路径每秒至少一有效观测，恢复10个连续一分钟窗口满足约定健康/读写与每窗口无失败 control；记录最小样本、每服务恢复预算/数据量/TTL/retention/lag数值。observer stale>15秒、未授权影响、数据异常、System/恢复受损、匹配/成本超限即停。目标预期高CPU不套非目标80%阈值。
Full infra proposes at least one valid observation per path per second and ten consecutive one-minute recovery windows meeting agreed health/read-write criteria with failure-free control windows. Record minimum samples, service recovery budgets, data volumes, TTL/retention and numeric lag caps. Stop for observer staleness >15 seconds, unauthorized impact, data anomalies, System/recovery damage or match/cost overrun. Expected target CPU pressure does not use the non-target 80% threshold.

### 3.2 后续真实业务流 / Later real business flows

| 对象 / Service | 中文业务与完整性契约 | Corresponding English business/integrity contract |
| --- | --- | --- |
| MySQL / PostgreSQL | 幂等订单、同事务库存、读已确认订单；独立 attempt/ack/unknown，唯一 effect，无半事务。未知 commit 按 key 先核对，不盲重写。 | Idempotent order, inventory in the same transaction, reads of acknowledged orders; independent attempt/ack/unknown, unique effects and no half-transactions. Reconcile unknown commits by key before rewriting. |
| 两种 Redis / Both Redis products | cache-aside、更新真值/失效回填；比对版本/新鲜度、hit/miss、后端负载，不以缓存当唯一持久数据。 | Cache-aside, source updates and invalidation/refill; compare versions/freshness, hit/miss and backing load, without treating cache as sole durable data. |
| Blob | 唯一 operation 上传/下载与中断重试；hash/length/ETag/version/ack 账本，无重复逻辑上传。 | Unique-operation upload/download and interrupted-transfer retry; hash/length/ETag/version/ack ledger, no duplicate logical uploads. |
| Service Bus | 发布订单事件→PeekLock→提交业务effect→settle；核对ack、attempt、唯一effect、outstanding/DLQ；不用ReceiveAndDelete验证持久业务。 | Publish order→PeekLock→commit effect→settle; reconcile ack, attempts, unique effects and outstanding/DLQ. Do not use ReceiveAndDelete for durable business verification. |
| Event Hubs | 已知partition唯一事件→提交effect→checkpoint；核对ack/unknown、offset/sequence、durable checkpoint；不承诺全局顺序/exactly-once。 | Unique events on known partitions→commit effect→checkpoint; reconcile ack/unknown, offsets/sequences and durable checkpoints; no global ordering/exactly-once guarantee. |
| Cosmos（后续选择） / Cosmos if selected | 明确partition key、并发/幂等、consistency/session/ETag、write-region/conflict，核对已确认/未知与新鲜度。 | Explicit partition key, concurrency/idempotency, consistency/session/ETag, write-region/conflicts; reconcile acknowledged/unknown outcomes and freshness. |
| RocketMQ（后续选择） / RocketMQ if selected | 固定ack/flush/replication契约，effect先提交后ack，核对broker/store、重投/retry/DLQ与唯一持久effect。 | Freeze ack/flush/replication guarantees, commit effects before ack, and reconcile broker/store health, redelivery/retry/DLQ and unique durable effects. |
| AKS | 故障期间实际应用流与Pod/node/events、请求、账本、放置容量/恢复关联。 | Correlate actual application flows with Pod/node/events, requests, ledgers, placement/capacity and recovery during faults. |

这些是参考流，实施前映射到真实接口/不变量；只有SDK直连时仅报告客户端库韧性。业务与独立验证 Job 在云端 AKS，ConfigMap脚本+固定已验证镜像、requests/limits、deadline/有限重试/清理，最小workload identity与secret引用，不挂host/Docker socket或放宽全局策略。proxy/hook须实际影响协议/持久连接/池及全部相关端点，保持TLS；control/ledger/recovery置故障外。默认900秒Job装不下15分钟基线+暴露+10分钟恢复，须获批有限分阶段并连续观察；间隙是缺证据。HTTPS socket timeout不是硬端到端deadline。
These are reference flows; map them to real interfaces/invariants before execution. SDK-only direct clients establish client-library resilience only. Run application and independent verification Jobs in cloud AKS using ConfigMap scripts, pinned validated images, requests/limits, deadlines, finite retries/cleanup, least-privilege workload identities and secret references; no host/Docker sockets or global policy relaxation. Proxies/hooks must affect actual protocols/persistent connections/pools/all relevant endpoints while retaining TLS. Keep control/ledger/recovery outside the fault. A default 900-second Job cannot fit a 15-minute baseline plus exposure plus ten-minute recovery; use approved finite phases with continuous observations, treating gaps as missing evidence. HTTPS socket timeout is not a hard end-to-end deadline.

### 3.3 待评审业务指标 / Proposed business acceptance targets

以下是项目建议，不是 Microsoft SLA，也不是已获批服务保证；实际执行前确认。当前原生阶段不以这些业务指标为额外前置。
These are project proposals, not Microsoft SLAs or approved service guarantees; confirm before execution. They are not additional prerequisites for the current native phase.

| 指标 / Dimension | 中文建议 | Corresponding English proposal |
| --- | --- | --- |
| 基线 / Baseline | 15分钟、至少1000逻辑业务操作、成功≥99.9%且符合应用latency SLO；低流量延长。 | 15 minutes, ≥1,000 logical business operations, ≥99.9% success within application latency SLO; extend low-volume runs. |
| 模拟 / Simulation | 初始60秒，干净恢复后才180秒；一个canary/依赖。同步deadline建议10秒，所有层合计最多3次重试，指数退避+jitter。 | Start at 60 seconds, expand to 180 only after clean recovery; one canary/dependency. Proposed synchronous deadline ten seconds, at most three retries across all layers with exponential backoff/jitter. |
| Cache fallback | 后端容量已证实时成功≥99%、p95≤2倍基线；否则明确有界失败。路径恢复后重连≤120秒，10分钟hit ratio回到基线±10个百分点。 | With verified backing capacity, ≥99% success and p95≤2× baseline; otherwise explicit bounded failure. Reconnect ≤120 seconds after path restoration and hit ratio within ten percentage points of baseline in ten minutes. |
| 硬依赖中断 / Hard dependency outage | 允许需要该依赖的操作在deadline内明确失败或按契约持久排队，无虚假成功；control仍满足基线。 | Dependent operations may explicitly fail within deadline or queue durably under contract; no false success, with control meeting baseline. |
| 短故障恢复 / Short-fault recovery | 移除模拟后120秒内回SLO，并持续10个一分钟窗口；不替代从故障开始计的RTO。 | Return to SLO within 120 seconds after simulation removal and sustain ten one-minute windows; this does not replace RTO from incident initiation. |
| DB HA | 建议端到端RTO≤180秒，已确认committed事务零丢失；核对真实负载、WAL/backlog、连接池。 | Proposed end-to-end RTO≤180 seconds and zero lost acknowledged committed transactions; qualify realistic load, WAL/backlog and connection pools. |
| 消息 / Messaging | 对账所有ack，无重复committed业务effect；恢复后10分钟排空有限backlog，遵循获批TTL/DLQ。 | Reconcile every ack, no duplicate committed business effects; drain bounded backlog within ten minutes under approved TTL/DLQ policy. |
| Storage planned | 独立3小时maintenance window，单次transition建议≤90分钟，按大小/features确认；无已确认对象丢失，failback另授权。 | Separate three-hour maintenance window; proposed ≤90 minutes per transition, qualified by size/features; no acknowledged object loss, with failback separately approved. |
| PITR/geo | 每目标确认RTO/RPO、备份/复制、数据量；异步复制/restore不默认零RPO。 | Agree per-target RTO/RPO, backup/replication and data volume; no default zero RPO for async replication/restoration. |

业务成功率=满足同步/持久接收契约的逻辑操作÷相关attempt，不是HTTP2xx/SQL ping/内存排队/Action成功。retry amplification=下游全部attempt÷原逻辑操作；另固定offered rate观察attempt rate。完整性=无丢ack持久effect/重复committed effect/破坏不变量，未解unknown为Inconclusive。RTO从注入/事件开始至持续SLO恢复；RPO以已确认数据缺口的数量/时间实测。每窗口有最小样本，缺窗口不能靠总p95通过。1000次的99.9%至多一失败，只是有限验收不是长期SLA认证；不从不足流量造p99。分别记录start/impact/alert/decision/recovery action/dependency/SLO/backlog，DR RTO含检测决策。
Business success rate is logical operations meeting synchronous/durable-acceptance contracts divided by relevant attempts, not HTTP2xx/SQL pings/in-memory queues/Action success. Retry amplification is all downstream attempts divided by original operations; freeze offered rate and separately observe attempt rate. Integrity means no missing acknowledged durable effects, duplicate committed effects or broken invariants; unresolved unknowns are Inconclusive. RTO runs from injection/incident to sustained SLO recovery; measure RPO as acknowledged data gaps in counts/time. Require minimum samples per window; aggregate p95 cannot pass missing windows. At 1,000 operations, 99.9% permits at most one failure, a finite check rather than long-term SLA certification; do not fabricate p99 with insufficient traffic. Record start/impact/alert/decision/recovery action/dependency/SLO/backlog separately; DR RTO includes detection and decision.

<a id="4-common-client-path-cases"></a>
## 4. 通用客户端补充场景 / Common Client-path Additions

保留原英文 C-family 五项；按实际产品/协议分别运行。均为后续模拟，不是已确认原生 Action；Pod-wide 网络影响全部容器/目的地址，不等价单依赖。身份refresh可未来以专用身份另审，不撤共享权限/生产凭据。
Retain all five former English C-family cases, running separately per actual product/protocol. They are later simulations, not confirmed native Actions. Pod-wide networking affects all containers/destinations and is not single-dependency isolation. Future identity-refresh drills require dedicated identities, not shared-permission/production-credential revocation.

| ID / 优先级 / Priority | 中文场景、边界与验收 | Corresponding English scenario, boundaries and acceptance |
| --- | --- | --- |
| C-01 / P0 | 单canary→单依赖的已有/新连接中断60秒，control不受影响；deadline/重试有界、无假成功/重复effect，移除后必要时仅重建受影响测试连接并实测恢复。 | Black out established/new connections from one canary to one dependency for 60 seconds, leaving control unaffected; bounded deadlines/retries, no false success/duplicate effects. Remove fault, rebuild only affected test connections if needed and prove recovery. |
| C-02 / P0 | 单路径+100ms、+500ms分别运行60秒，不改共享路由；池/worker队列有界，timeout/circuit breaker合契约，记录p95/p99/重试，移除后队列池恢复。 | Separate +100ms and +500ms 60-second runs on one path, no shared-route changes; bounded pools/worker queues, contractual timeouts/circuit breakers, p95/p99/retries recorded, queues/pools restored after removal. |
| C-03 / P0 | 有限合成请求到达服务后切断响应/settlement，必要时protocol-aware hook；核对全部unknown、每ID唯一effect、无ack持久丢失，移除后全量对账。 | Let bounded synthetic requests reach the service, then interrupt responses/settlement using protocol-aware hooks where needed; reconcile every unknown, unique effects per ID and no lost acknowledged durable work, then remove and reconcile all IDs. |
| C-04 / P1 | 仅测试workload依赖hostname解析失败60秒，分别测试复用/新连接；依赖告警、有界失败、重新解析/连接，恢复测试局部DNS，旧socket正常不证明DNS覆盖。 | Fail only test-workload dependency hostname resolution for 60 seconds, testing reused/new connections; dependency alerts, bounded failures and re-resolution/reconnect. Restore test-local DNS; healthy old sockets do not prove DNS coverage. |
| C-05 / P1 | 按真实SDK错误模拟限流/资源限制，429/503仅适用HTTP，不伪造SQL/Redis/AMQP HTTP错误；仅重试可重试项、尊重server delay、并发有界、无OOM/storm，移除排空恢复。 | Simulate SDK-correct throttling/resource limits; 429/503 only for applicable HTTP APIs, never fabricated SQL/Redis/AMQP HTTP errors. Retry eligible errors only, honor server delay, bound concurrency, prevent OOM/storms, remove, drain and recover. |

<a id="5-service-specific-test-cases"></a>
## 5. 中文主线与保留的服务用例 / Chinese-led and Retained Service Cases

以下先按用户中文资源顺序列VM、AKS、MySQL、Storage、Legacy Redis、Event Hubs、LB/Gateway，再列英文原有补充的PostgreSQL、Managed Redis、Service Bus、Cosmos和RocketMQ业务。稳定Case ID不改；所有行中文/英文同步，继承§0.2/§3/§7/§9。§0.5才是当前执行状态，以下机制/验收不是已运行声明。
The order follows supplied Chinese resources first: VM, AKS, MySQL, Storage, Legacy Redis, Event Hubs and LB/Gateway; then retained English additions: PostgreSQL, Managed Redis, Service Bus, Cosmos and RocketMQ business. Stable Case IDs are unchanged. Every row is synchronized bilingually and inherits §0.2/§3/§7/§9. Current execution status is in §0.5; definitions below do not claim execution.

### 5.1 VM 基础设施 / VM infrastructure

V-03–V-10 不替代broker业务V-01/V-02；复用VM时仍核对所有消费者/数据/中断。OS、broker持久数据、backend/evidence/恢复盘不作为disk目标，jumpserver排除。
V-03–V-10 do not substitute for broker business V-01/V-02. Reusing a VM still requires all consumer/data/interruption checks. Exclude OS, broker durable data, backend/evidence/recovery disks and jumpservers.

| ID / Priority | 中文场景、前置与验收恢复 | Corresponding English scenario, prerequisites and recovery acceptance |
| --- | --- | --- |
| V-03 / P1 | CPU pressure原生Continuous；单agent-qualified VM、OS/identity/outbound/headroom核验，默认≤50%，更高另opt-in/授权。实测CPU达批准范围、非目标/观察可用；结束效果消失、CPU/guest/技术读写恢复，未达效果不通过。 | Native Continuous CPU pressure; one agent-qualified VM with OS/identity/outbound/headroom verified, default ≤50%, higher levels separately opted in/approved. Measure approved CPU effect and healthy non-target/observation paths; verify effect removal, CPU/guest/read-write recovery. Unachieved effect does not pass. |
| V-04 / P1 | 物理内存压力Continuous，pressureLevel 1–99、初始≤50%，保留guest/recovery能力；90%/关键OOM另审。实测memory/OOM/进程事件，未授权损伤即停；移除后内存/guest/技术读写恢复，不称真实泄漏。 | Continuous physical memory pressure, pressureLevel 1–99, initial ≤50%, preserving guest/recovery headroom; separately review 90%/critical OOM. Observe memory/OOM/process events, stop unauthorized damage, verify memory/guest/read-write recovery after removal; not a real leak. |
| V-05 / P1 | 指定目的地址/port/protocol/方向的latency/jitter，当前原生未映射，guest模拟另审；保存interface/qdisc/routes和owned handle，建议+100ms/60秒。实测协议影响/control，仅移除本次规则并比原配置；ping不替代协议。 | Destination/port/protocol/direction latency/jitter, currently native-unmapped; separately review guest simulation. Preserve interface/qdisc/routes and owned handles, proposed +100ms/60 seconds. Prove protocol impact/control, remove only owned rules and compare original configuration; ping is not protocol evidence. |
| V-06 / P1 | 单目的路径loss，独立于V-05，初始1%/60秒、足够样本、owned rules/独立恢复；不改共享NSG/DNS/管理链路。证明丢包/重试/timeout，移除后协议与规则恢复，观察断开即独立停。 | Single-destination loss, separate from V-05, initial 1%/60 seconds with sufficient samples, owned rules and independent recovery; no shared NSG/DNS/management changes. Prove loss/retries/timeouts, restore protocol/rules after removal and stop independently on observation loss. |
| V-07 / P1 destructive | 专用可销毁卷的有限owned文件耗尽bytes/inodes，精确mount/path/上限/保留空间/硬deadline、snapshot恢复，不填OS/broker卷；fallocate未必产生真实效果。验证限定写失败，其他卷健康；只删确切文件，空间/inodes/原合成数据读写恢复，损坏不会因cleanup自动修复。 | Exhaust bytes/inodes with bounded owned files on a disposable volume, exact mount/path/caps/reserve/hard deadline and snapshot recovery, never OS/broker volumes; fallocate may not achieve the intended effect. Prove scoped write failure and healthy other volumes; delete exact files only and verify space/inodes/original synthetic data. Cleanup does not repair corruption. |
| V-08 / P1 | 专用卷IO压力，限定workers/IOPS/bytes/rate/精确PID/文件/成本/deadline；先测盘型/配额/latency/queue，不混V-07、不碰OS/broker/evidence。实测压力/节流，终止精确进程并清owned files后IO/guest/数据恢复。 | Dedicated-volume IO pressure with bounded workers/IOPS/bytes/rate/exact PIDs/files/cost/deadline. Baseline disk type/quotas/latency/queues; separate from V-07 and exclude OS/broker/evidence. Prove pressure/throttling, stop exact processes/clean owned files and verify IO/guest/data recovery. |
| V-09 / P1 | 单VM一次Discrete restart，核对ID、全部消费者、boot/guest/服务runbook、备份、独立恢复；不重复restart。Azure operation+boot/guest/协议证明恢复，Running不足；不可undo，恢复超限/关键数据损伤Failed，不替代broker durability。 | One Discrete VM restart after ID/all-consumer/boot/guest/service-runbook/backup/independent-recovery checks; no repeated restart. Prove operation, boot/guest and protocol recovery, not merely Running. No undo; recovery overrun/critical-data damage is Failed, not broker-durability acceptance. |
| V-10 / P1 | 单operation-owned测试进程termination/supervisor恢复，精确PID/executable/start identity/owner、操作前防PID reuse；不批量kill、不杀broker/agent/system、不关VM。目标/机制未确认则NotRun；证实旧进程终止、新进程技术行为恢复，只清本次进程。 | Terminate one operation-owned test process and recover via its supervisor, checking exact PID/executable/start identity/owner and PID reuse immediately before action. No bulk kills, broker/agent/system termination or VM shutdown. Unqualified target/mechanism stays NotRun; prove old termination/new technical behavior and clean only owned processes. |

### 5.2 AKS Pod / AKS Pods

使用operator-owned [extension][aks-extension]，不默认Chaos Mesh。五个URN均1.0.0，结构duration至少PT1M、实际效果遵守§3 bounds；namespace匹配安装、精确AND labels含chaos-canary=target，禁止default/system/control/verification或wildcard。核对Linux/amd64/工具、admission、网络与私有支持。private/Cilium/mesh部分配置未验证，不等于永久不支持；PSA-restricted pod-delete helper可能失败。PDB不保证注入删除/节点丢失受自愿驱逐保护。
Use the operator-owned extension, not default Chaos Mesh. Five URNs use 1.0.0, structural duration ≥PT1M and effects within §3 bounds. Namespaces must match installation, with exact AND labels including chaos-canary=target; no default/system/control/verification/wildcards. Qualify Linux/amd64/tools, admission, networking and private support. Some private/Cilium/mesh configurations are unvalidated, not permanently unsupported; pod-delete helpers may fail under restricted PSA. PDBs do not guarantee injected deletion/node loss follows voluntary-eviction protections.

| ID / Priority | 中文场景与验收恢复 | Corresponding English scenario and recovery acceptance |
| --- | --- | --- |
| K-01 / P0 | `urn:csci:microsoft:containerservice:poddelete/1.0.0`；graceful、精确cohort/比例取整/替换成员、interval大于暴露。验证原Pod真删除、新Pod服务技术/业务流；delete不可取消，停止后续注入、核controller/readiness/账本。 | Graceful pod deletion with exact cohort/rounding/replacement membership and interval beyond exposure. Prove original deletion and replacement technical/business traffic; deletion is not cancelable. Stop further injection and verify controllers/readiness/ledgers. |
| K-02 / P1 | `urn:csci:microsoft:containerservice:podcpuhog/1.0.0`；工具/架构合格，容量允许才从1core、≤60秒。测latency/队列、邻居/control、实际HPA不假定扩容；移除后CPU/Ready/阶段SLO恢复。 | Qualified tools/architecture; begin at one core only within capacity, ≤60 seconds. Measure latency/queues, neighbors/control and actual HPA rather than assuming scaling; remove and verify CPU/Ready/phase-SLO recovery. |
| K-03 / P1 | `urn:csci:microsoft:containerservice:podmemoryhog/1.0.0`；指定container/headroom、1–128MB/比例、承认OOM风险。验证memory/OOM/restart与持久工作，无邻居/node损伤；移除并恢复副本/阶段SLO，不称逐步泄漏。 | Explicit container/headroom, 1–128MB/approved percentage with OOM risk acknowledged. Verify memory/OOM/restarts and durable work without neighbor/node damage; remove and restore replicas/phase SLO. Not a progressive leak. |
| K-04 / P1 | `urn:csci:microsoft:containerservice:podnetworklatency/1.0.0`；network daemon合格，+100ms起、≤60秒，授权含sidecar。测真实latency/池/retry/control；移除后核全部连通/helper/container restart，不能只看Succeeded。 | Qualified network daemon, start +100ms, ≤60 seconds, including sidecars in approval. Measure actual latency/pools/retries/control; after removal verify all connectivity/helper/container restarts, not just Succeeded. |
| K-05 / P1 | `urn:csci:microsoft:containerservice:podnetworkloss/1.0.0`；1%起、≤60秒、充足流量，不用100%默认。测loss/unknown/latency/attempt，提前helper删除使暴露未证实；移除后实际连通恢复，必要替换Pod另授权。 | Start at 1% loss, ≤60 seconds with sufficient traffic, no 100% default. Measure loss/unknowns/latency/attempts; early helper deletion leaves exposure unproven. Verify real connectivity after removal; separately authorize Pod replacement if needed. |
| K-06 / P1 | 单Pod专用进程逐步内存增长，明确rate/bytes/终点/deadline/node headroom；原生未映射，本轮不编模拟。以后测增长曲线、limits/OOM/restart/非目标/数据；仅终止owned进程或获批替换，持续Ready/读写、无增长残留。 | Progressive memory growth in one dedicated Pod process with rate/bytes/end/deadline/node headroom. Native-unmapped, no simulation this phase. Later measure growth curve, limits/OOM/restart/non-target/data; terminate only owned processes or approved replacement, with sustained Ready/read-write and no residue. |

网络效果可能在container restart后仍残留，即使run为Succeeded；必须实测清除，受影响测试Pod替换另授权，不全局放宽策略。
Network effects may persist after container restart even with a Succeeded run. Prove removal; replacement of affected test Pods needs separate approval, not global policy relaxation.

### 5.3 AKS 节点与 ASM / AKS Nodes and ASM

通过AKS nodeResourceGroup发现VMSS/实际实例/zones，不硬编码MC_*、不import管理VMSS生命周期；NAP排除。节点故障不依赖Pod extension；核真实副本/存储/剩余容量/autoscaler/AKS reconciliation，控制/账本/恢复放故障外。
Discover VMSS/instances/zones via AKS nodeResourceGroup, not hardcoded MC_* names or imported VMSS lifecycle ownership; exclude NAP. Node faults do not require the Pod extension. Check actual replica/storage/spare capacity/autoscaler/AKS reconciliation and keep control/ledger/recovery outside the fault.

| ID / Priority | 中文场景、范围与恢复 | Corresponding English scenario, scope and recovery |
| --- | --- | --- |
| N-01 / P1 | 获批User-pool zone失效，VMSS shutdown明确region/zone并核全部匹配；独立窗口排System/恢复池，容量/副本/storage合格。证明节点失效/技术或业务恢复，停止后Ready/容量/存储；不声称完整可用区停机或自动重新分布。 | Approved User-pool zone loss via VMSS shutdown with exact region/zone and all matches checked; separate window excluding System/recovery pools with capacity/replica/storage qualification. Prove unavailable nodes and phase recovery, then Ready/capacity/storage; not a complete AZ outage or guaranteed redistribution. |
| N-02 / P1 | node CPU pressure精确agent/instance scope待核，不压整池或用Pod hog替代。核vCPU/headroom/Pod放置，测主机CPU与隔离；移除后node/Pod/容量恢复，记录autoscaler。 | Exact agent/instance scope for node CPU pressure awaits qualification; no whole-pool pressure or Pod-hog substitution. Check vCPU/headroom/Pod placement, prove host CPU and containment; restore node/Pod/capacity and record autoscaler behavior. |
| N-03 / P1 | node物理memory压力，核bytes/pressure/timeout/eviction/OOM与System/恢复排除；实例/恢复未核不运行。证明主机memory/eviction与受损，未授权组件受损即停；容量/数据/调度恢复，不假定迁回原node。 | Node physical-memory pressure with bytes/pressure/timeout/eviction/OOM and System/recovery exclusions; no run before instance/recovery qualification. Prove host memory/eviction/impact, stop unauthorized component damage, restore capacity/data/scheduling without assuming return to the original node. |
| N-04 / P1 | 单node目的路径loss，原生未映射；interface/instance/owned rules/全部Pod-sidecar/guest恢复须明确，不改共享网络/全namespace。证实node-wide协议loss与control隔离，恢复原网络/Ready；K-05不能替代。 | Single-node destination-path loss, native-unmapped; require exact interface/instance/owned rules/all Pods-sidecars/guest recovery, no shared network/all-namespace changes. Prove node-wide protocol loss/control containment and original network/Ready restoration; K-05 is not a substitute. |
| N-05 / P1 | 单node latency/jitter，与N-04分开，低强度短时、保存原配置、独立stop；主机路径latency实证，移除owned效果后协议/Ready恢复，缺证据不通过。 | Single-node latency/jitter, separate from N-04, low intensity/short duration with saved configuration and independent stopping. Prove host-path latency and protocol/Ready restoration after owned-effect removal; missing evidence does not pass. |
| N-06 / P2 high-risk | 单node→API Server partition，PendingDesign/另审，不运行；精确API路径/lease/eviction/影响/ARM-guest恢复/硬deadline，不共享route或/dev/null，不假定4分钟安全。证明partition与lease/Ready相关，恢复调度/网络/数据；失控或超恢复限Failed。 | Single-node→API Server partition, PendingDesign/separate review, no run; exact API path/lease/eviction/impact/ARM-guest recovery/hard deadline, no shared routes or /dev/null and no assumed four-minute safety. Correlate partition with lease/Ready and restore scheduling/network/data; loss of control or recovery overrun is Failed. |
| N-07 / P1 | 仅一User node不可用，zone筛选实际匹配必须恰一；多实例即不运行、不随机deleteinstances，运行前重查System排除/半池容量/存储。实际实例失效与恢复/数据/容量有证据，不冒充N-01，记录新扩容量。 | Exactly one unavailable User node; zone filter must actually match one instance. Multiple matches mean no run, never random deleteinstances. Recheck System exclusion/half-pool capacity/storage before execution. Prove instance impact/recovery/data/capacity, not N-01; record added autoscaler capacity. |
| I-01 / P2 | ASM/Istio指定proxy与control断连，核mesh/revision/连接基线/namespace/独立恢复；AwaitingTarget/PendingDesign，不装mesh补齐。未来独立模拟审查，证明仅获批连接丢失/重同步/技术流量/原网络；Pod-wide loss不等价、不同于N-06。 | Disconnect selected ASM/Istio proxies from control, checking mesh/revisions/connection baseline/namespaces/independent recovery. AwaitingTarget/PendingDesign; no mesh installation for coverage. Separately review future simulation and prove approved-only disconnection/resync/traffic/original network; Pod-wide loss is not equivalent, and this differs from N-06. |

### 5.4 MySQL Flexible Server

合格HA/backup/FQDN/事务幂等前置，区分SameZone/ZoneRedundant；HA/restart不是region outage。典型60–120秒failover不是应用RTO保证，geo-restore另核geo backup。参见[HA][mysql-ha]、[备份恢复 / backup/restore][mysql-backup]。
Qualify HA/backups/FQDN/transaction idempotency and distinguish SameZone/ZoneRedundant. HA/restart is not region outage; typical 60–120-second failover is not application RTO. Geo-restore separately requires geo backups.

| ID / Priority | 中文场景与验收恢复 | Corresponding English scenario and recovery acceptance |
| --- | --- | --- |
| M-01 / P0 | HA primary failover，单HA服务器一次；完整业务参考duration5分钟须schema确认，本轮实际1分钟，RestoreOnStop=false避免未审第二切换。持续事务核ack零丢失、库存不变量、FQDN池恢复/HA RTO；新primary/HA健康，回切另授权。 | One HA primary failover on one server; five-minute full-business reference duration requires schema validation, while actual native runs used one minute. RestoreOnStop=false avoids an unreviewed second transition. Under transactions verify no lost acks, inventory invariants, FQDN-pool recovery/HA RTO; healthy new primary/HA, separately approved failback. |
| M-02 / P0 | 单次Discrete重启，非定时60秒outage；明确失败/安全重试、不需人工重启应用。实测outage、无storm/半事务/重复订单，Ready后重建stale连接、核数据与阶段SLO。 | One Discrete restart, not a timed 60-second outage; explicit failure/safe retry without manual app restart. Measure outage, no storm/half-transactions/duplicate orders; after Ready rebuild stale connections and verify data/phase SLO. |
| M-03 / P1 | PITR：记录checkpoint，只改合成数据，恢复到新隔离server，不是Chaos failover。核恢复点前记录/不变量、RTO/RPO、身份/私网，不覆盖/销毁源；cutover/临时资源清理另授权。 | PITR: record checkpoint, alter synthetic data only and restore to a new isolated server, not Chaos failover. Verify pre-checkpoint records/invariants, RTO/RPO, identities/private networking; never overwrite/destroy source, separately approve cutover/temporary cleanup. |
| M-04 / P1 | 实际独立read replica客户端路径不可用，不能用HA standby；精确目标/lag/测试流量/control，禁共享NSG改动。机制未确认NotRun；未来局部模拟证明replica路径失效/主路径健康，恢复连接/lag/合成读，不声称服务或复制链路停机。 | Unavailable client path to an actual independent read replica, not HA standby; exact target/lag/test traffic/control, no shared NSG changes. Unconfirmed mechanism stays NotRun. Later local simulation proves replica-path loss/healthy primary, restores connections/lag/synthetic reads, not service or replication outage. |

### 5.5 Blob Storage

仅Blob，Files/ADLS Gen2/Queue/Table需独立变体；当前ZRS不合geo切换。账户级动作含全部服务/实体，排backend/backup/shared/恢复依赖。planned要求两区可用/同步完成，不测试真实primary-region unavailable；可约1小时、GZRS→GRS等冗余变化需实测，回切另授权。unplanned可能丢未复制数据/去geo/不一致，默认排除。参见[限制 / DR restrictions][storage-dr]、[planned][storage-planned]、[前置 / prerequisites][storage-start]。
Blob only; Files/ADLS Gen2/Queue/Table need separate variants. Current ZRS is not geo-failover eligible. Account-wide effects include all services/entities; exclude backend/backup/shared/recovery dependencies. Planned failover requires both regions available and sync complete, not actual primary-region unavailability; it may take about an hour and alter redundancy such as GZRS→GRS, requiring observation and separate failback approval. Unplanned failover can lose unreplicated data/remove geo redundancy/create inconsistencies and is excluded by default.

| ID / Priority | 中文场景与验收恢复 | Corresponding English scenario and recovery acceptance |
| --- | --- | --- |
| S-01 / P0 | Blob连接reset/transient，复用C-01/C-03/C-05，专用container/prefix/有限60秒流量；上传真实成功或有界失败，hash/length/ack对账，无重复逻辑对象；移除后核中断上传/读写。 | Blob reset/transient errors using C-01/C-03/C-05 on a dedicated container/prefix with bounded 60-second traffic; truthful completion/bounded failure, hash/length/ack reconciliation and no duplicate logical objects; remove and reconcile interrupted uploads/read-write. |
| S-02 / P1 | RA-GRS/RA-GZRS只读secondary fallback，实际service/private access合格；不向secondary写，未复制对象按freshness契约处理非宣称丢失；恢复primary路径与应用回归。 | Read-only secondary fallback on qualified RA-GRS/RA-GZRS with verified service/private access; no secondary writes, handle not-yet-replicated objects under freshness contract rather than declaring loss; restore primary/application routing. |
| S-03 / P1 account-wide DR | 专用合格geo账户planned failover，独立3小时窗口、同步/两区健康；审HNS/change feed/object replication/policies/全部服务，Files停止所有client/share activity。核RTO/ack对象/私网DNS，另授权failback并恢复冗余/复制/Files remount；Discrete不可undo。 | Planned failover on a dedicated eligible geo account, separate three-hour window with synchronization/both-region health; review HNS/change feed/object replication/policies/all services and stop Files client/share activity. Verify RTO/acknowledged objects/private DNS; separately approve failback and confirm redundancy/replication/Files remount. Discrete, no undo. |
| S-04 / P1 recovery | 专用保护已启用/retention合格的合成Blob误删/覆盖，version/soft-delete恢复，非region failover；核准确content/version/hash/RTO，不覆盖新有效数据，仅清获批对象。 | Delete/overwrite synthetic Blob in a dedicated protection-enabled/retention-qualified fixture, restore via version/soft-delete rather than region failover; verify exact content/version/hash/RTO, never overwrite newer valid data and clean approved objects only. |

### 5.6 Legacy Azure Cache for Redis

仅Microsoft.Cache/redis Basic/Standard/Premium reboot，不是CDN/Enterprise/Managed Redis；replica需Standard/Premium，Basic的R-02为Blocked。现有部署可测，迁移Managed Redis不是本计划任务。参见[管理 / administration][cache-admin]。
Reboot covers Microsoft.Cache/redis Basic/Standard/Premium, not CDN/Enterprise/Managed Redis. Replica tests require Standard/Premium; R-02 on Basic is Blocked. Existing deployments may be tested; migration to Managed Redis is not part of this plan.

| ID / Priority | 中文场景与验收恢复 | Corresponding English scenario and recovery acceptance |
| --- | --- | --- |
| R-01 / P0 | PrimaryNode reboot，单实例/cluster先单明确ShardId并路由keys；核cache-aside fallback/后端负载/拓扑/值/回暖，无缓存持久保证，不选AllNodes。 | PrimaryNode reboot on one cache, initially one explicit ShardId for clusters with keys routed there; verify cache-aside fallback/backing load/topology/values/warm-up, no cache durability guarantee and no AllNodes. |
| R-02 / P1 | SecondaryNode reboot，合格副本一次，不能同时主故障；应用/control符合SLO、副本重加入与冗余真实恢复。 | One SecondaryNode reboot on a qualified replica with no concurrent primary fault; application/control SLO, actual replica rejoin and restored redundancy. |
| R-03 / P1 | 有限热合成keys expire/invalidate hook，非默认全库flush；回填并发有界、值正确/真值健康/回暖达标；停hook，仅重建测试keys。 | Expire/invalidate bounded hot synthetic keys via a hook, not default full flush; bounded refill concurrency, correct values/healthy source/warm-up; disable hook and rebuild test keys only. |
| R-04 / P1 destructive | 全数据库flush，Legacy原生Workspace Action未确认，受控data-plane drill另审；专用独占可重建、实际cluster/database/消费者/TLS/Entra，不启keys、不删sessions/唯一持久数据。核实际全范围删除与重建版本/读写，少量key仅R-03；无undo，恢复失败Failed。 | Full database flush, no confirmed Legacy Workspace Action; separately review a controlled data-plane drill. Require exclusive reconstructible database, actual cluster/database/consumers/TLS/Entra; no access keys or sessions/sole-durable-data deletion. Prove full scoped removal/reconstruction/versions/read-write; bounded keys are R-03 only. No undo, recovery failure is Failed. |

reboot不是flush，仍可能丢近期cache writes；不能从控制面成功推零丢失。
Reboot is not flush and may lose recent cache writes; control-plane success does not establish zero loss.

### 5.7 Event Hubs

专用hub/group、故障外checkpoint，核partitions/retention/ack/replay容量。它是保留分区流，非SB队列，无PeekLock/settlement或通用DLQ；backlog按partition lag/time/bytes，retention须覆盖故障+最差replay+证据余量。H-05/H-06是独立geo专项，不将entity state称region outage。参见[Geo-DR][eh-geodr]、[Geo-Replication][eh-georep]。
Use dedicated hub/group and outside-fault checkpoints; qualify partitions/retention/ack/replay capacity. This is a retained partitioned stream, not an SB queue, with no PeekLock/settlement/general DLQ. Assess backlog by per-partition lag/time/bytes; retention must exceed disruption+worst replay+evidence margin. H-05/H-06 are separate geo drills; entity states are not region outages.

| ID / Priority | 中文场景与验收恢复 | Corresponding English scenario and recovery acceptance |
| --- | --- | --- |
| H-01 / P0 | 单hub SendDisabled、显式eventhubs、60秒须schema核验/有限publisher；持久outbox或deadline明确失败，观察既有consumer、ack/unknown，恢复原状态/replay/排积压。 | One hub SendDisabled, explicit eventhubs, schema-qualified 60 seconds/bounded publishers; durable outbox or explicit deadline failure, observe existing consumers and ack/unknown, restore prior state/replay/drain. |
| H-02 / P1 | 单隔离hub Disabled独立运行，原状态/group/checkpoint/retention记录；真实send/receive影响，不假定新attempt均保留；恢复后从durable checkpoint重放并retention前对账全部ack。 | Separate Disabled run on one isolated hub with prior state/group/checkpoints/retention recorded; prove send/receive effects, not assumed retention of new attempts. Restore/replay from durable checkpoints and reconcile all acks before retention expiry. |
| H-03 / P0 | effect commit后checkpoint前终止consumer，用hook或合格Pod delete，不用entity state；有限cohort/group、checkpoint不故障。允许重投但每ID唯一effect、遵守partition顺序契约；重平衡/offset核对/按deadline排空。 | Terminate consumer after effect commit before checkpoint using hook/qualified Pod delete, not entity state; bounded cohort/group, never fault checkpoint storage. Allow redelivery but one effect per ID and contractual partition order; rebalance/reconcile offsets/drain by deadline. |
| H-04 / P1 | 暂停专用consumer/path，有限producer继续，属consumer simulation非namespace outage；明确rate/总量/lag/bytes/retention，不撤共享SAS/RBAC。测partition积压/ack，恢复正确checkpoint追赶/重放，不能越过未committed effect，预算未确认NotRun。 | Pause dedicated consumer/path while finite publishing continues; consumer simulation, not namespace outage. Bound rate/volume/lag/bytes/retention, never revoke shared SAS/RBAC. Prove partition backlog/ack, resume from correct checkpoints/replay without skipping uncommitted effects; unconfirmed budgets mean NotRun. |
| H-05 / P2 regional | metadata Geo-DR alias failover，专用primary/secondary/pairing/私网/RBAC/旧events-checkpoint恢复获批；不复制事件。验证alias/new endpoint读写，单独说明旧侧可读/重放/缺失，断pairing后恢复另审，非自动failback/零丢失。 | Metadata Geo-DR alias failover with approved dedicated primary/secondary/pairing/private access/RBAC/old-event-checkpoint recovery; no event replication. Verify alias/new endpoint read-write, separately account for old-side readability/replay/gaps; re-pairing separately reviewed, not automatic failback/zero loss. |
| H-06 / P2 regional | data Geo-Replication promotion，实际region/SKU/API/sync-async/复制健康/私网/checkpoint/RPO获批；Standard/zone HA不自动合格，默认不强提async。逐partition/ID/ack/unknown核数据与唯一effect，未知gap Inconclusive，重同步/回切另审。 | Data Geo-Replication promotion qualified by region/SKU/API/sync-async/replication health/private access/checkpoints/RPO; Standard/zone HA is not automatically eligible and forced async promotion is not default. Reconcile partition/ID/ack/unknown and unique effects, unknown gaps Inconclusive, separately review resync/failback. |

### 5.8 Load Balancer / Application Gateway（未来补充 / Future）

当前无获批目标，不动AKS托管LB、不建Gateway填数量；AGFC/LB/Gateway不同产品。后续核SKU/backend/probe/routing、owning state、最小权限、control和恢复。
No approved current targets; do not fault AKS-managed LB or create Gateways for counts. AGFC/LB/Gateway are different products. Later qualify SKU/backend/probe/routing, owning state, least privilege, control and recovery.

| ID / Priority | 中文场景与验收恢复 | Corresponding English scenario and recovery acceptance |
| --- | --- | --- |
| L-01 / P1 Future | 单backend unavailable，后续核microsoft-network-updateloadbalanceradminstate/1.0与区域schema，精确pool/address/count/原admin state；证实流量摘除/control，恢复state/probe/routing，admin Down不证明VM崩溃。 | Single-backend unavailability; later verify microsoft-network-updateloadbalanceradminstate/1.0/regional schema, exact pool/address/count/prior state. Prove traffic removal/control and restore state/probe/routing; admin Down is not VM crash. |
| L-02 / P1 Future | 单backend网络路径中断，机制另映射，不与admin-state等价；精确destination/owned rules/独立恢复、不共享NSG/DNS，测network/probe/routing/control，移除后原连接恢复。 | Single-backend network interruption, mechanism separately mapped, not admin-state equivalence; exact destination/owned rules/independent recovery, no shared NSG/DNS. Measure network/probe/routing/control, remove and restore connectivity. |
| L-03 / P1 Future | 单backend probe异常，专用responder/hook另审，准确protocol/port/path/threshold，不改共享probe；实测状态/摘除/恢复时间，ping不替代probe。 | Single-backend probe failure via separately reviewed dedicated responder/hook; exact protocol/port/path/threshold, no shared-probe changes. Prove state/traffic removal/recovery timing; ping is not probe evidence. |
| G-01 / P1 Future | 单backend进程/实例故障，明确native/simulation；实际Gateway/SKU/pool/listener/routing/control/恢复。证实backend health/路由/响应及恢复，不称Gateway整体失效。 | Single-backend process/instance failure with explicit native/simulation classification; actual Gateway/SKU/pool/listener/routing/control/recovery. Prove backend health/routing/responses and restoration, not whole-Gateway failure. |
| G-02 / P1 Future | 单backend目的网络中断，精确rules/独立恢复，不改共享NSG/DNS/TLS；实测Gateway health/routing/control，移除owned规则后原网络恢复。 | Single-backend destination network interruption with exact rules/independent recovery, no shared NSG/DNS/TLS changes. Prove Gateway health/routing/control and original-network restoration after owned-rule removal. |
| G-03 / P1 Future | 单backend probe异常，实际protocol/hostname/path/threshold/原配置与专用responder；证实probe failure/摘除/恢复流量时间线，非ping/配置保存成功。 | Single-backend probe failure with actual protocol/hostname/path/threshold/prior configuration and dedicated responder; prove probe failure/traffic removal/recovery timeline, not ping/configuration-save success. |

### 5.9 PostgreSQL Flexible Server（保留补充 / Retained addition）

核HA primary/standby、tier/FQDN/pool/backup，不以replica promotion替代HA。WAL/workload可能延长恢复，SameZone不证明zone-loss，HA RPO不套异步跨区。参见[HA][pg-ha]、[备份 / backup][pg-backup]。
Qualify HA primary/standby, tier/FQDN/pools/backups; replica promotion is not HA substitution. WAL/workload may extend recovery, SameZone does not prove zone loss, and HA RPO does not cover async cross-region replication.

| ID / Priority | 中文场景与验收恢复 | Corresponding English scenario and recovery acceptance |
| --- | --- | --- |
| P-01 / P0 | PlannedFailover一次，RestoreOnStop=false、不跳不合格；完整参考duration5分钟待schema、本轮1分钟。核ack committed写、in-flight安全完成/重试/unknown、pool/RTO/角色/HA，之后才下一切换。 | One PlannedFailover, RestoreOnStop=false, no ineligible skipping; five-minute full reference subject to schema, native runs one minute. Reconcile acknowledged committed/in-flight/retried/unknown writes, pools/RTO/roles/HA before another transition. |
| P-02 / P1 | P-01干净恢复后另授权ForcedFailover，先记录WAL backlog/长事务；健康HA目标下ack committed零丢失、unknown核对/replay时间，HA/阶段SLO恢复，failback另审。 | Separately approved ForcedFailover after clean P-01 recovery, recording WAL backlog/long transactions. For healthy HA require no lost acknowledged committed writes, unknown reconciliation/replay timing, HA/phase-SLO restoration and separate failback approval. |
| P-03 / P1 | retained/available backup内PITR到新隔离server不替源；核records/schema/app兼容/私网/身份/RTO/restore gap，只清获批临时fixture且保留证据。 | PITR within retained/available backups to a new isolated server without source replacement; verify records/schema/app compatibility/private networking/identity/RTO/restore gap, clean only approved temporary fixtures after evidence retention. |

### 5.10 Azure Managed Redis（保留补充 / Retained addition）

redisEnterprise资源名不证明产品/SKU；先核是可重建cache或sessions/持久state，异步不零丢失。[架构 / architecture][amr-waf]、[geo][amr-geo]供核对。Geo Replication Healthy不是数值lag，应用version markers测freshness。export/import默认不含，private-link/firewall限制不通过弱化网络绕过。
redisEnterprise resource naming does not prove product/SKU. Distinguish reconstructible cache from sessions/durable state; async replication is not zero loss. Geo Replication Healthy is not numeric lag; measure freshness via application version markers. Export/import is excluded by default; do not weaken networks to bypass private-link/firewall restrictions.

| ID / Priority | 中文场景与验收恢复 | Corresponding English scenario and recovery acceptance |
| --- | --- | --- |
| A-01 / P0 | C-01 cluster-aware客户端60秒断连，单canary/database路径，不声称node reboot；验证fallback/deadline/topology/真值/回暖，移除后真实请求恢复。 | C-01 cluster-aware client disconnection for 60 seconds on one canary/database path, not node reboot; prove fallback/deadline/topology/source/warm-up and real-request recovery after removal. |
| A-02 / P1 destructive | 原生flush专用可重建database，geo-linked时全部linked caches均独占可删获批；未知属性PendingVerification、待删除许可AwaitingAuthorization、已知不可重建Blocked。测fallback/后端/回暖，擦除无undo，不触唯一business/session数据。 | Native flush of a dedicated reconstructible database; all geo-linked caches must also be exclusive/disposable/approved. Unknown properties PendingVerification, deletion AwaitingAuthorization, known non-reconstructible data Blocked. Verify fallback/backing load/warm-up; erasure has no undo, never sole business/session data. |
| A-03 / P1 regional | 隔离区域测试clients并应用endpoint/identity重定向，专用合格active geo group/HA/SKU/version/modules/配置/私网；核RTO/freshness-RPO/并发写/alternate健康、路径恢复后convergence，非Azure区域故障，不切service replication。 | Isolate regional test clients and redirect app endpoint/identity on a dedicated eligible active geo group/HA/SKU/version/modules/configuration/private access. Verify RTO/freshness-RPO/concurrent writes/alternate health and convergence after path restoration; not Azure-region or service-replication outage. |
| A-04 / P2 topology | force-unlink明确linked IDs，专用disposable group与恢复生命周期另授权；健康成员/memory/replication实证，必要删除重建受影响成员按runbook获批，重join/convergence后回流；不是故障注入或自动re-link。 | Force-unlink explicit linked IDs on a dedicated disposable group with separately approved recovery lifecycle; prove healthy members/memory/replication, approve required affected-member deletion/recreation under runbook, rejoin/converge before return. Not outage injection or automatic re-link. |

### 5.11 Service Bus（保留补充 / Retained addition）

专用queue/topic/subscription、有限backlog/TTL，持久业务用PeekLock。Geo-Replication复制metadata+messages/state；sync/async不同，forced async可能丢数据/重复，默认排除。Geo-DR与其互斥、仅metadata不含queue/subscription/DLQ数据，alias failover断pairing；若用Geo-DR另定义outbox/replay/re-pairing，不冒充B-05。核secondary RBAC/私网。[locks][sb-locks]、[Geo-Replication][sb-georep]、[Geo-DR][sb-geodr]。
Dedicated queues/topics/subscriptions, bounded backlog/TTL and PeekLock for durable business. Geo-Replication copies metadata+messages/state; sync/async differ, and forced async promotion may lose data/duplicate effects, excluded by default. Mutually exclusive Geo-DR copies metadata only, not queue/subscription/DLQ data, and alias failover breaks pairing. Existing Geo-DR requires a separate outbox/replay/re-pairing drill, not B-05 substitution. Qualify secondary RBAC/private access.

| ID / Priority | 中文场景与验收恢复 | Corresponding English scenario and recovery acceptance |
| --- | --- | --- |
| B-01 / P0 | 单queue SendDisabled/显式queues/60秒schema合格；发送明确失败或durable outbox，旧消息仍消费，ack/unknown核对；原状态恢复、replay/唯一effect。 | One queue SendDisabled with explicit queues/schema-qualified 60 seconds; explicit send failures or durable outbox, existing-message consumption, ack/unknown reconciliation; restore prior state/replay/unique effects. |
| B-02 / P0 | 单queue ReceiveDisabled60秒、有限publisher；证明send/积压告警/预算与无损，恢复原状态/send/receive/settle，排空无重复committed effect。 | One queue ReceiveDisabled for 60 seconds with bounded publishers; prove send/backlog alerts/caps/integrity, restore prior state/send/receive/settle and drain without duplicate committed effects. |
| B-03 / P1 | topic与subscription disable分别运行、精确列表、Discrete、operator持有60秒后显式恢复；核接收/拒绝与所有受影响subscriptions，不假定disabled持续积压；Cancel亦须原状态恢复/对账DLQ。 | Separate topic/subscription disable runs with exact lists, Discrete actions and operator-managed 60-second hold before explicit restoration. Verify accepted/rejected work/all affected subscriptions, no assumed backlog accumulation while disabled; restore prior state/reconcile DLQ even after Cancel. |
| B-04 / P0 | consumer effect commit→complete间隙断连接/锁/settlement，另测handler delay超过lock renewal budget；有限cohort，不改全局锁。重投允许每ID唯一effect/DLQ对账；移除后排空或显式dead-letter测试消息/核renewal。 | Interrupt connection/lock/settlement between consumer-effect commit and completion; separately test handler delay beyond lock-renewal budget. Bounded cohort, no global lock changes. Allow redelivery with one effect per ID/DLQ reconciliation; remove, drain or explicitly dead-letter test messages and verify renewal. |
| B-05 / P2 regional | 合格专用Premium同步secondary的planned Geo-Replication promotion，region/identity/私网已核，不是queue Action。稳定hostname恢复、ack消息/state保留、RTO/ledger通过，重同步与reverse promotion另审；不套metadata-only Geo-DR。 | Planned Geo-Replication promotion on dedicated eligible Premium with synchronized secondary and verified region/identity/private access, not queue Action. Stable-hostname recovery, retained acknowledged messages/state, RTO/ledger acceptance; separately review resync/reverse promotion, not metadata-only Geo-DR. |

### 5.12 Cosmos DB（保留但本轮不选 / Retained, Unselected）

NoSQL契约，其他API独立SDK/error/consistency变体；单region不能运行offline-region，partition/consistency/session/write region/conflict先确认，不为覆盖新增region。[可靠性 / reliability][cosmos-reliability]。
NoSQL contract; other APIs need distinct SDK/error/consistency variants. Single-region accounts do not qualify for offline-region; agree partition/consistency/session/write-region/conflicts first, without adding regions for coverage.

| ID / Priority | 中文场景与验收恢复 | Corresponding English scenario and recovery acceptance |
| --- | --- | --- |
| D-01 / P1 | C-01/C-03/C-05的NoSQL transport/throttle模拟，专用items/keys/canary60秒，不降共享吞吐；retry-after/deadline、ack/unknown/ETag/consistency对账，移除后读写，不称实际region/RU耗尽。 | NoSQL transport/throttle simulation via C-01/C-03/C-05 on dedicated items/keys/canary for 60 seconds, no shared-throughput reduction; reconcile retry-after/deadlines/ack/unknown/ETag/consistency and restore read-write, not actual region/RU exhaustion. |
| D-02 / P2 regional | 合格多region账户offline-region/显式RegionName，全账户受影响clients纳授权非container scope；核读写mode/RTO/RPO/conflict/alternate、ack持久工作在契约内，region重入/复制/回流实证，Cancel非恢复证明；当前Unselected。 | Offline-region with explicit RegionName on eligible multi-region account; authorize account-wide affected clients, not container scope. Verify modes/RTO/RPO/conflicts/alternate and acknowledged durability under contract, prove reintegration/replication/return traffic; Cancel is not recovery. Currently Unselected. |

### 5.13 RocketMQ 业务（保留但本轮不选 / Retained, Unselected）

standalone重启可真实停服，只接受明确有界失败或批准持久排队，不虚构HA；disk/sync-async flush/replication决定ack durability。
A standalone restart may legitimately interrupt service; accept explicit bounded failures or approved durable queues, not invented HA. Disk/sync-async flush/replication determine ack durability.

| ID / Priority | 中文场景与验收恢复 | Corresponding English scenario and recovery acceptance |
| --- | --- | --- |
| V-01 / P1 | 原生VM restart下broker durability；专用private broker/topics/groups、NameServer/standalone-HA声明、非jumpserver。核broker/store/reconnect/ack-unknown/唯一effect，systemd/bootstrap/registration/send-consume持续恢复非VM Running；本轮不选。 | Broker durability under native VM restart; dedicated private broker/topics/groups, documented NameServer/standalone-HA and no jumpserver. Prove broker/store/reconnect/ack-unknown/unique effects and sustained systemd/bootstrap/registration/send-consume recovery, not VM Running; unselected. |
| V-02 / P2 deferred | 原生V-03/V-04有界CPU/memory提供机制，专用VM/OS/identity/public outbound/headroom/存储合格，agent安装保留；另验broker retry/backlog/durable ack/真实压力/业务恢复，本轮业务不选，不阻塞独立VM前置。 | Bounded native V-03/V-04 CPU/memory provides mechanisms on qualified dedicated VM/OS/identity/public outbound/headroom/storage, with agent retained. Separately verify broker retries/backlog/durable acks/real pressure/business recovery; unselected business does not block independent VM preparation. |

<a id="6-end-to-end-extension-after-individual-services-pass"></a>
## 6. 后续业务流程验证 / Later Business-flow Validation

E-family保留原英文验收，均后续business，不以前置infra/原生结果关闭；跨依赖业务流仍每次只故障一个依赖，组合故障另需新假设/累计预算/授权。
Retain original English E-family acceptance for later business phases; infra/native results do not close them. Multi-dependency business flows still use one fault per run; combined faults need a new hypothesis/cumulative budget/approval.

| ID / Priority | 中文场景与验收 | Corresponding English scenario and acceptance |
| --- | --- | --- |
| E-01 / P1 | cache-only故障下实际cache-aside订单流，不同时故障DB；后端headroom/业务SLO/有限回填/正确订单。 | Cache-only fault during actual cache-aside order flow, never simultaneous DB fault; verify backing headroom/business SLO/bounded refill/correct orders. |
| E-02 / P1 | B-01下订单→DB commit→outbox→SB；核committed订单、保留outbox、最终唯一consumer effect/排积压；无已证应用模式不称跨服务原子。 | B-01 during order→DB commit→outbox→SB; prove committed order/retained outbox/eventual unique consumer effect/backlog drain; no cross-service atomicity without a proven app pattern. |
| E-03 / P1 | K-01下真实consumer与B-04/H-03有限cohort，只一个Pod故障；对账重启前ack、retry/redelivery、每ID唯一durable downstream effect。 | K-01 on actual consumer with bounded B-04/H-03 cohort and one Pod fault; reconcile pre-restart acks/retries/redelivery and unique durable downstream effects per ID. |

<a id="7-safety-permissions-stopping-and-restoration"></a>
## 7. 授权、执行、停止与恢复 / Authorization, Execution, Stopping and Restoration

### 7.1 完整阶段标准步骤 / Full-phase execution steps

当前原生先行按§0.6最短流程，不新增SDK/账本/observer门槛；以下完整infra/business仍保留全部安全与验收要求。文档批准不授权部署/流量/故障，已授权正常前置可一起准备，扩大/破坏/共享生命周期另审。
Current native-first work follows §0.6 without new SDK/ledger/observer gates; full infra/business retains the following safety/acceptance contract. Document approval does not authorize deployment/traffic/faults. Ordinary prerequisites within an approved scope may be prepared together; expansion/destruction/shared lifecycle needs separate review.

| 步骤 / Step | 中文操作与必要记录 | Corresponding English operation and records |
| --- | --- | --- |
| 1 资格 / Qualification | ID/variant/phase、真实目标/消费者/排除、catalog/schema/region/SKU/HA、identity/权限、数值预算/窗口/cost、恢复operator；无冲突维护/运行。 | ID/variant/phase, actual targets/consumers/exclusions, catalog/schema/region/SKU/HA, identities/rights, numeric budgets/window/cost and recovery operator; no conflicting maintenance/runs. |
| 2 审plan / Plan review | 固定工具/readonly lock、fmt/validate/相关tests/lint/policy；owning state私有saved plan审create/update/delete/replace、RBAC/network/cost。 | Pinned tools/readonly lock, fmt/validate/targeted tests/lint/policy; private owning-state saved plan reviewed for create/update/delete/replace, RBAC/network/cost. |
| 3 部署发现 / Deploy/discover | 仅授权同一saved plan，核provisioning/真实RBAC传播/发现排除/实体实例；保留原安装/state，无schedule/run。 | Apply only the authorized reviewed saved plan; verify provisioning/actual RBAC propagation/discovery exclusions/entities/instances. Preserve installation/state, no schedule/run. |
| 4 基线 / Baseline | 云端AKS技术或真实业务流、独立control/ledger/observer、容量/retention/保护/samples/deadline；演练通知/独立恢复，ConfigMap脚本不等于可用stop链。 | Cloud AKS technical/real business flow, independent control/ledger/observer, capacity/retention/protection/samples/deadlines; rehearse notification/independent recovery. ConfigMap scripts are not an operational stop path. |
| 5 单故障 / One fault | 重查动态Pod/node/VMSS/entity最大匹配与授权后显式启动；不Terraform/provisioner/pipeline自动run，不自动加压/restart/failover/修权限。 | Recheck dynamic Pod/node/VMSS/entity maximum matching and approval, then explicitly start; no Terraform/provisioner/pipeline auto-runs or auto-pressure/restarts/failovers/permission fixes. |
| 6 观察 / Observe | Chaos/operation、guest/events、protocol/metrics关联injection/impact/alert/decision；未命中/不足强度/Skipped缺证据不通过。 | Correlate Chaos/operations, guest/events and protocol/metrics across injection/impact/alert/decision; missed/under-strength/Skipped effects do not pass. |
| 7 停止恢复 / Stop/restore | 独立通知operator，Cancelable/Continuous移除并实证；Discrete/transition只按获批runbook、不竞争failover；恢复原entity/network或明确接受new primary。 | Notify independent operator, remove Cancelable/Continuous effects with proof; Discrete/transitions follow approved runbook, no competing failover. Restore prior entity/network state or explicitly accept new primary. |
| 8 稳定清理 / Sustain/clean | 逐窗口phase标准/数据/HA/容量/backlog/规则无残留，private scoped plan调查drift不自动apply；只清owned PID/rule/file/Job/IAM/临时资源。 | Windowed phase criteria/data/HA/capacity/backlog/no residue; investigate drift via private scoped plan, no automatic apply. Clean only owned PIDs/rules/files/Jobs/IAM/temporary resources. |
| 9 报告 / Report | 每variant/phase中文+对应英文依据、真实结果/限制/私有证据；Future/Unselected/NotRun不填Passed。 | Per-variant/phase Chinese plus corresponding English rationale, actual verdict/limitations/private evidence; Future/Unselected/NotRun are not Passed. |

部署身份、Workspace runtime、operator、业务workload分离；custom role按验证输出最小目标授权，Reader与Action/cluster operator不同。实验窗口避免Terraform/GitOps纠正仅故意临时状态，不关闭无关controller或永久宽ignore_changes。模拟/native机制缺支持先另审，不用旧chaos run或多Action模板冒充授权。
Separate deployer, Workspace runtime, operator and app identities. Derive custom least-privilege target rights from validation; Reader differs from Action/cluster-operator rights. During approved windows prevent correction of intentional temporary state only, without disabling unrelated controllers or broad permanent ignore_changes. Unqualified simulation/native mechanisms require separate review, not old chaos run examples or multi-Action-template authorization.

### 7.2 停止阈值与恢复完成 / Stop thresholds and recovery completion

以下业务阈值待执行前调优映射到真实observer/检测预算/operator；预期依赖失败不自动终止，隔离/数据/恢复失控必须停止。原生阶段预算见§0.6。
Tune the following business thresholds before execution and map each to actual observers/detection budgets/operators. Expected dependency failures are not automatic aborts; loss of containment/integrity/recovery requires stopping. Native-phase budgets are in §0.6.

| 中文停止条件 | Corresponding English stop condition |
| --- | --- |
| 任一未授权目标/control受损、ack持久数据丢失、重复业务effect、破坏事务或异常腐败/假成功。 | Any unauthorized/control impact, lost acknowledged durable data, duplicate business effects, broken transactions, corruption or false success. |
| control成功<99%持续60秒，或p95>2倍基线60秒；retry attempt rate>3倍基线30秒。 | Control success <99% for 60 seconds or p95>2× baseline for 60 seconds; retry attempt rate >3× baseline for 30 seconds. |
| 非预期目标/后端CPU或memory>80%、连接>实测上限80%，持续60秒；压力目标预期高值另按授权。 | Unexpected target/backing CPU or memory >80%, or connections >80% of verified limit, for 60 seconds; expected pressure-target values follow approval. |
| SB backlog达5000或实体容量70%先到者；EH/RocketMQ按每partition/time/bytes/retention数字上限，不照抄队列数。 | SB backlog reaches 5,000 or 70% entity capacity, whichever first; EH/RocketMQ use numeric per-partition/time/bytes/retention caps, not queue counts. |
| observer stale>15秒、恢复/观察访问丢失、窗口/成本/匹配范围超限。 | Observer stale >15 seconds, lost recovery/observation access, or window/cost/matching overrun. |

availability evaluator仅样本窗口/silence/monitor budget/可选latency-consecutive-failure，不实现全部时间规则/CPU/backlog/integrity、不Cancel/restore；其Passed不是case Passed。缺证据Inconclusive并停止升级，不伪装健康。Continuous/Cancelable停止也须验证效果消失；restart/flush/unlink/failover无undo，不发竞争切换。
The availability evaluator covers sample windows/silence/monitor budgets/optional latency-consecutive failures, not every time rule/CPU/backlog/integrity and not cancellation/restoration. Its Passed is not case Passed. Missing evidence means Inconclusive plus stop/escalation, not healthy fallback. Continuous/Cancelable stopping still requires effect-removal proof; restart/flush/unlink/failover has no undo, and no competing transition is allowed.

恢复完成：实际网络/协议正常、原状态或获接受新primary、HA/replication/容量正常、cache回暖、backlog/DLQ/全部attempt-ack-unknown对账；完整infra每窗口技术/control通过，business持续10分钟SLO/不变量通过，互不替代。private drift审查不自动apply恢复旧拓扑，只清owned资源保留证据，不destroy代替停止/恢复。
Recovery completion requires actual network/protocol health, prior state or deliberately accepted new primary, healthy HA/replication/capacity, cache warm-up, backlog/DLQ/all attempt-ack-unknown reconciliation. Full infra needs every technical/control window; business needs ten minutes of SLO/invariants, without substitution. Review private drift without auto-applying old topology, clean only owned resources and retain evidence; destroy is not cancellation/recovery.

<a id="8-dependency-ordered-delivery-and-execution-waves"></a>
## 8. 实施任务与执行批次 / Implementation Tasks and Execution Waves

以下为完整阶段工程路径，不新增当前原生测试前置；已有安装不重复预算/部署，已知geo/Pod阻塞不阻塞独立合格PaaS。
These are full-phase engineering paths, not new current native prerequisites. Do not re-budget/redeploy existing installations; geo/Pod gaps do not block independently eligible PaaS cases.

| Task / 依赖 / Dependency | 中文交付与出口 | Corresponding English deliverable and exit |
| --- | --- | --- |
| T0 / 无 / none | app/platform owner确认私有ID/variant/phase/target/state、契约/资格/cost/window/恢复授权；各case明确合格或具体缺项。 | App/platform owner freezes private ID/variant/phase/target/state, contract/eligibility/cost/window/recovery approval; each case qualified or explicitly pending. |
| T1 / T0 | Terraform owner核原state/迁移/locked schema/plan，无重复归属/扩权限/意外替换；bootstrap/migration仅另行必要且获批。 | Terraform owner checks existing state/migration/locked schema/plan, no duplicate ownership/widening/replacement; bootstrap/migration only if independently necessary/approved. |
| T2 / T0+该case获批前置 / approved case prerequisites | app/evidence owner建技术control/协议/独立ledger/采样/retention/stop通知，后续business adapter；获批基线与silence/恢复演练通过，Job默认off。 | App/evidence owner delivers technical control/protocol/independent ledger/sampling/retention/stop notification, later business adapters; approved baseline/silence/recovery rehearsals pass, Jobs default off. |
| T3 / T1 | Chaos owner核service-direct参数/目标/最小rights、传播后Validate，解析/排除匹配manifest；无auto-repair/run，写配置不依赖T2。 | Chaos owner verifies service-direct parameters/targets/minimal rights, validates after propagation and matches resolved/excluded lists to manifest; no auto-repair/run, authoring independent of T2. |
| T4 / T1+T0目标 / target | AKS operator引用已装extension/connection/federation/ownership，核架构/镜像/admission/cleanup；不重复安装，runtime另等T2/T5。 | AKS operator references installed extension/connection/federation/ownership, qualifies architecture/images/admission/cleanup; no duplicate install, runtime waits for T2/T5. |
| T5 / T2+适用T3或T4 / applicable T3 or T4 | operator/app owner审配置/流量/run/recovery授权后单case云端验收；真实作用/隔离/阶段/数据/持续恢复，诚实结果不按数量完成。 | Operator/app owner reviews configuration/traffic/run/recovery approval then qualifies one cloud case; actual impact/containment/phase/data/sustained recovery, honest verdicts rather than count-based completion. |
| T6 / 相关T5干净恢复+扩大范围T0 / clean relevant T5 + expanded T0 | service owner逐case扩展；destructive/DR/agent/node另审支持/cost/ownership，不自动加压/重复。 | Service owner expands per case; separately reviews destructive/DR/agent/node support/cost/ownership, no automatic escalation/repetition. |
| T7 / 每次T5/T6 / each T5/T6 | evidence/Terraform owner对账、private drift、owned清理、报告/regression；未解drift/data指定owner/下一步。 | Evidence/Terraform owner reconciles, reviews private drift, cleans owned assets and reports/regresses; unresolved drift/data has an owner/next step. |

代码配置变更同时补约束/行为tests，静态fmt/readonly backend-disabled init/validate/mock/unit/TFLint/policy不算云验收；不全局suppress。真实apply tests、云plan/deploy/流量/fault分别授权。T1/T2可在T0后并行，但基线等该case前置；T3/T4独立分支。
Add focused constraint/behavior tests with corresponding code changes; static fmt/readonly backend-disabled init/validate/mocks/units/TFLint/policy are not cloud acceptance, with no global suppressions. Real apply tests/cloud plans/deployments/traffic/faults need relevant separate approval. T1/T2 may progress after T0, but baseline waits for case prerequisites; T3/T4 are independent branches.

| Wave | 中文范围与出口 | Corresponding English scope and exit |
| --- | --- | --- |
| 0 无故障 / No fault | T0–T4与该case前置/基线/stop演练；缺项明确不影响其他合格case。 | T0–T4, case prerequisites/baseline/stop rehearsal; explicit gaps do not block other eligible cases. |
| 1 最小影响 / Minimal | 合格A-01/C-01/S-01/B-01/H-01/K-01，真实作用/完整infra隔离数据恢复；无注入连接不能通过。 | Eligible A-01/C-01/S-01/B-01/H-01/K-01 with actual impact/full infra containment/data/recovery; connectivity without injection cannot pass. |
| 2 entity/HA | C-02/C-04/C-05、M-02/M-01/P-01、R-02后R-01/R-03、B-02/B-03/H-02/H-04，V-09另审；真实恢复/Discrete清理，无自动重复。 | Applicable client/entity/HA cases, R-02 before R-01/R-03 and separately reviewed V-09; actual restoration/Discrete cleanup, no automatic repeats. |
| 3 pressure/node | 合格K-02–K-06、V-03–V-06/V-08、N-02–N-05/N-07、P-02；I-01/N-06独立设计审查；agent/实例/容量/规则合格、逐级效果。 | Qualified Pod/VM/node-pressure/network cases and P-02; I-01/N-06 need separate design review. Require agent/instance/capacity/rule qualification and progressive measured effects. |
| 4 destructive/geo | V-07/V-10、R-04/A-02、S-04/S-02/S-03、H-05/H-06/M-04及另选PITR/geo/zone；逐目标数据/备份/复制/role/cost/不可逆恢复授权，不自动建目标。 | Separately qualified destructive/recovery/geo/replica and additionally selected PITR/zone cases; per-target data/backup/replication/role/cost/irreversible-recovery approval, no automatic fixtures. |
| 5 business/future | E-family、原business契约；D/V broker另选、L/G有真实获批目标才测；完整业务不被infra替代。 | E-family/original business contracts; D/V broker only if selected and L/G only with actual approved targets; infra never substitutes for business. |

低风险先一次，修复后建议三次连续干净运行；destructive/DR重复另审。成本包含HA/两个Redis/geo成员、SB Premium secondary、geo storage、私网/Jobs/Chaos/monitor/evidence/temp恢复，按region/SKU/量/时长估计、硬上限与cleanup owner，无默认批准价格。SDK/retry/network变化重跑约定回归，DR按季度或业务风险审查；coverage仅信息信号非全局百分比门槛。
Start low-risk cases once, then seek three consecutive clean runs after fixes; destructive/DR repetition needs separate review. Budget HA/both Redis products/geo members/SB Premium secondary/geo storage/private networking/Jobs/Chaos/monitor/evidence/temporary recovery by region/SKU/volume/duration, with hard caps/cleanup owners and no assumed price approval. Regress agreed cases after SDK/retry/network changes; review DR quarterly or by business risk. Coverage is informational, not a global percentage gate.

<a id="9-evidence-and-result-classification"></a>
## 9. 证据与结果 / Evidence and Verdicts

### 9.1 私有manifest与报告 / Private manifest and report

稳定case key+唯一private run reference，逐variant/phase必填；不适用/缺项说明原因，不留空或虚构Passed。原生记录与完整阶段模板分别使用，不以完整business字段阻塞当前原生。
Use stable case keys plus unique private run references with required per-variant/phase fields; explain inapplicability/gaps instead of blanks/fabricated Passed. Native records and full-phase templates are distinct; full-business fields do not block current native work.

| 类别 / Group | 中文必填 | Corresponding English required fields |
| --- | --- | --- |
| 身份范围 / Identity/scope | case/variant/hypothesis/flow-SDK、commit/worktree、environment/state、授权/operator私有、真实direct/indirect目标/排除。 | Case/variant/hypothesis/flow-SDK, commit/worktree, environment/state, private authorization/operator, exact direct/indirect targets/exclusions. |
| 机制 / Mechanism | simulation/service-direct/extension/agent/native drill、Workspace region/Action/API/schema参数、实际entity/pod/node、强度/暴露/最大影响。 | Mechanism classification, Workspace region/Action/API/schema parameters, actual entities/Pods/nodes, intensity/exposure/maximum impact. |
| 阶段 / Phase | infra技术/health/read-write/integrity/窗口samples/deadline/retry/recovery/retention；business实际flow/SLO/RTO/RPO/不变量/幂等/consistency；后续字段明确deferred。 | Infra technical/health/read-write/integrity/window samples/deadline/retry/recovery/retention; business flow/SLO/RTO/RPO/invariants/idempotency/consistency; explicitly mark deferred fields. |
| 安全 / Safety | 数字阈值/observer/检测预算/owner、独立恢复、原entity/topology、backup/replication、批准stop/recovery/cleanup/cost/window。 | Numeric thresholds/observers/detection budgets/owners, independent recovery, prior entity/topology, backup/replication and approved stop/recovery/cleanup/cost/window. |
| 观察 / Observation | UTC时间线+monotonic elapsed、真实impact/control/target metrics/raw counts、alert/stop交接、ack/unknown对账、恢复/drift、hash/retention。 | UTC timeline+monotonic elapsed, actual impact/control/target metrics/raw counts, alert/stop handoff, ack/unknown reconciliation, recovery/drift, hashes/retention. |
| 结论 / Decision | 原生run/Action、管理面影响恢复、完整infra/business分列，双语依据/限制、owner/下一步/未解问题/私有位置。 | Separate native run/Action, management impact/recovery and full infra/business verdicts, with bilingual rationale/limitations, owner/next step/unresolved issues/private location. |

账本必须在故障依赖/canary lifecycle外，重启不能抹ack真值；按契约核attempt/ack/unknown/persisted/consumed/failed，retry不等于唯一ID。原始run/日志/state/plan/kubeconfig/端点token/秘密只私有；公开脱敏真实资源/registry/repository/context/地址/tenant/subscription/run/request/contact/credentials。私有运行输入、代码和证据统一当前项目，路径按runbook §8.1，不复制为第二套清单。
Ledgers must survive outside faulted dependencies/canary lifecycles; restarts cannot erase ack truth. Reconcile attempt/ack/unknown/persisted/consumed/failed under contract; retries are not unique IDs. Keep raw runs/logs/state/plans/kubeconfigs/tokenized endpoints/secrets private; redact real resources/registries/repositories/contexts/addresses/tenant/subscription/run/request/contact/credentials publicly. Keep private inputs/code/evidence in this project under runbook §8.1, not a second catalog.

### 9.2 结果枚举 / Verdicts

| Result | 中文判定 | Corresponding English meaning |
| --- | --- | --- |
| Passed | 真实获批目标/流量受预期故障，所记录phase标准、完整性、恢复均有证据；管理面Passed仅该层，不是完整infra/business。 | Intended fault affected approved target/traffic with evidenced recorded-phase criteria/integrity/recovery. Management-plane Passed covers that layer only, not full infra/business. |
| Failed | 已运行但标准失败、隔离越界或恢复失败。 | Executed fault failed criteria, violated containment or failed recovery. |
| Inconclusive | 无真实影响/流量命中、证据不足、未证韧性或Skipped；完整未验证结果明确注明。 | Missing actual impact/traffic, insufficient evidence, unproven resilience or Skipped; explicitly mark full unverified outcomes. |
| Blocked | 已证实目标/机制不兼容或复现未解preflight，未执行；说明范围/证据/补救。普通配置/验证/授权待办用准备状态+NotRun，现有runner拒绝门槛不变。 | Evidenced target/mechanism incompatibility or reproduced unresolved preflight failure with no execution; specify scope/evidence/remedy. Ordinary configuration/verification/authorization gaps use preparation status+NotRun; existing runner rejection gates remain unchanged. |

原生Succeeded不是完整Passed；静态validation/mock/plan/Ready/本地probe不算云故障验收。coverage若计百分比须披露固定selected-case分母，不把未选/待办/Skipped/Blocked算成功。历史“未启动故障”只描述准备阶段；当前以§0.5及原生报告两轮证据为准，不能覆盖已执行事实。
Native Succeeded is not full Passed; static validation/mocks/plans/Ready/local probes are not cloud fault acceptance. Disclose a fixed selected-case denominator for any coverage percentage and never count unselected/pending/Skipped/Blocked as success. Historical “no fault started” statements describe preparation only; §0.5 and the report's two-round evidence govern current execution facts.

<a id="10-decisions-and-completion-checklist"></a>
## 10. 完成检查 / Completion Checklist

当前先保留已执行9项结果/限制，Redis优先补独立影响证据；AKS先补既有私网观察/动态放置/恢复证据，不以重新执行或新增应用掩盖缺项。其余按§0.5资格/授权推进，完整业务另阶段。此文档整理只交付清晰同步清单，不执行云操作，不新增客户签署门槛。
Retain the nine executed cases' results/limitations; prioritize independent Redis impact evidence. Obtain existing private AKS observation/dynamic-placement/recovery evidence first, rather than hiding gaps through re-execution/new apps. Progress remaining cases by §0.5 qualification/authorization, with business in a later phase. This documentation change delivers a clear synchronized catalog only, executes no cloud operations and adds no customer sign-off gate.

- [ ] 目标/variant/phase/owner、原state归属、原生支持/身份/授权完整。 / Targets/variants/phases/owners, original state ownership, native support/identity/approval complete.
- [ ] 静态/policy/plan结果与云证据分列，无意外delete/replace/网络/RBAC扩大。 / Static/policy/plan results separated from cloud evidence, no unexpected delete/replace/network/RBAC expansion.
- [ ] 所选完整阶段云端基线/独立stop/recovery已演练，原生层不假称完成完整门槛。 / Selected full-phase cloud baseline/independent stop/recovery rehearsed, without treating native evidence as full gates.
- [ ] 各实际run命中/隔离/阶段数据/恢复/结果诚实可审计；70定义不等于70通过。 / Each run has auditable impact/containment/phase data/recovery/honest verdict; 70 definitions do not mean 70 passes.
- [ ] 实际效果消失、HA/容量/数据/backlog/窗口恢复证据完整。 / Actual effect removal, HA/capacity/data/backlog/windowed recovery evidenced.
- [ ] private drift审查、仅owned临时资源清理、原始证据保留。 / Private drift reviewed, owned temporary assets only cleaned, raw evidence retained.
- [ ] Failed/Blocked/Inconclusive/NotRun/Unselected/Future均原因与owner明确，无全矩阵认证。 / All failures/gaps/unselected/future cases have reasons/owners, no full-matrix certification.
- [x] 全部70编号与39中文映射保留，中文/英文同结构同步；英文额外场景已补中文。 / All 70 IDs and 39 Chinese mappings retained, with synchronized bilingual structure and Chinese counterparts for additional English cases.

## 官方参考 / Official References

沿用2026-11-23对catalog/Workspace/targeting/ARM/least-privilege、AKS/geo/storage等的复核记录；其他背景链接来自2026-11-20，实施时更新所选case。本文语言整理未重新联网核验产品支持，文档支持不等于当前订阅/资源资格。
Retain recorded 2026-11-23 reviews of catalog/Workspace/targeting/ARM/least privilege and AKS/geo/storage guidance; other background links originate from 2026-11-20 and require refresh for selected cases. This language edit does not freshly verify online product support; documentation is not live subscription/resource qualification.

- [Well-Architected 韧性测试 / Reliability testing][waf]
- [Workspaces 概述 / Overview][workspaces]
- [支持资源与 Action catalog / Supported resources and Actions][catalog]
- [目标筛选与验证 / Targeting and validation][targeting]
- [最小权限 / Least-privilege roles][leastpriv]
- [Scenario ARM/AzAPI schema][scenario-schema]
- [AKS extension 前置与已知限制 / Requirements and known issues][aks-extension]
- [AKS extension 安装与参数 / Installation and parameters][aks-install]
- [AKS node/VMSS 测试 / Testing guidance][aks-nodes]
- [Cosmos DB 可靠性与区域恢复 / Reliability and regional recovery][cosmos-reliability]
- [MySQL HA][mysql-ha] / [备份恢复 / Backup and restore][mysql-backup]
- [PostgreSQL HA][pg-ha] / [备份恢复 / Backup and restore][pg-backup]
- [Legacy Redis reboot/flush 管理 / Administration][cache-admin]
- [Managed Redis 架构 / Architecture][amr-waf] / [Geo-replication / force-unlink][amr-geo]
- [Storage DR 限制 / Restrictions][storage-dr] / [planned failover][storage-planned] / [前置 / Prerequisites][storage-start]
- [Service Bus locks/settlement][sb-locks] / [Geo-Replication][sb-georep] / [Geo-DR][sb-geodr]
- [Event Hubs metadata Geo-DR][eh-geodr] / [data Geo-Replication][eh-georep]

[waf]: https://learn.microsoft.com/en-us/azure/well-architected/reliability/reliability-test
[workspaces]: https://learn.microsoft.com/en-us/azure/chaos-studio/chaos-studio-workspaces-overview
[catalog]: https://learn.microsoft.com/en-us/azure/chaos-studio/chaos-studio-workspaces-supported-resources
[targeting]: https://learn.microsoft.com/en-us/azure/chaos-studio/chaos-studio-workspaces-resource-targeting
[leastpriv]: https://learn.microsoft.com/en-us/azure/chaos-studio/chaos-studio-workspaces-least-privilege-roles
[scenario-schema]: https://learn.microsoft.com/en-us/azure/templates/microsoft.chaos/2026-08-01-preview/workspaces/scenarios
[aks-extension]: https://learn.microsoft.com/en-us/azure/chaos-studio/chaos-studio-aks-extension-overview
[aks-install]: https://learn.microsoft.com/en-us/azure/chaos-studio/chaos-studio-aks-extension-install
[aks-nodes]: https://learn.microsoft.com/en-us/azure/chaos-studio/chaos-studio-aks-guidance
[cosmos-reliability]: https://learn.microsoft.com/en-us/azure/reliability/reliability-cosmos-db
[mysql-ha]: https://learn.microsoft.com/en-us/azure/mysql/flexible-server/concepts-high-availability
[mysql-backup]: https://learn.microsoft.com/en-us/azure/mysql/flexible-server/concepts-backup-restore
[pg-ha]: https://learn.microsoft.com/en-us/azure/postgresql/high-availability/concepts-high-availability
[pg-backup]: https://learn.microsoft.com/en-us/azure/postgresql/backup-restore/concepts-backup-restore
[cache-admin]: https://learn.microsoft.com/en-us/azure/azure-cache-for-redis/cache-administration
[amr-waf]: https://learn.microsoft.com/en-us/azure/well-architected/service-guides/azure-managed-redis
[amr-geo]: https://learn.microsoft.com/en-us/azure/redis/how-to-active-geo-replication
[storage-dr]: https://learn.microsoft.com/en-us/azure/storage/common/storage-disaster-recovery-guidance
[storage-planned]: https://learn.microsoft.com/en-us/azure/storage/common/storage-failover-customer-managed-planned
[storage-start]: https://learn.microsoft.com/en-us/azure/storage/common/storage-initiate-account-failover
[sb-locks]: https://learn.microsoft.com/en-us/azure/service-bus-messaging/message-transfers-locks-settlement
[sb-georep]: https://learn.microsoft.com/en-us/azure/service-bus-messaging/service-bus-geo-replication
[sb-geodr]: https://learn.microsoft.com/en-us/azure/service-bus-messaging/service-bus-geo-dr
[eh-geodr]: https://learn.microsoft.com/en-us/azure/event-hubs/event-hubs-geo-dr
[eh-georep]: https://learn.microsoft.com/en-us/azure/event-hubs/geo-replication
