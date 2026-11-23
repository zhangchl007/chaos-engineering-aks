# Azure Chaos Studio 统一测试用例与覆盖规范

**Reviewed:** 2026-11-23.  
**Status:** 唯一测试用例清单；原生运行记录已生成，完整 infra/business 尚未验收。文档整理不授权部署、流量或故障执行。  
**Scope:** 指定非生产资源组内的 VM、AKS、MySQL、PostgreSQL、两种 Redis、Blob Storage、Service Bus、Event Hubs；AKS 托管节点资源组是唯一经规划确认的例外。Cosmos DB、RocketMQ 业务验证本轮不选；LB/Application Gateway 留作未来补充。

本文合并原 PaaS/Terraform 清单及用户提供的 4.1–4.8 场景，保留原 43 个用例编号，补充 27 个不同故障边界/验收目标的用例，共 **70 个规范用例**。用户场景去重后为 39 项，与规范编号的映射见 §0.4；一个场景可包含多个独立变体，不等于一次组合故障。相同机制但不同验收层级不重复执行或冒充另一个用例通过。

[实施计划](./chaos-studio-implementation-plan.md)仅跟踪工程批次，[部署与测试 runbook](./terraform-deployment-runbook.md#chaos-test-operations)统一保存全部操作步骤、安装、停止恢复和报告流程；用例定义、范围与验收以本文为准，不再创建另一份测试用例清单。测试代码、配置样例与私有运行输入均统一放置在当前项目，位置见 runbook §8.1。

**Next step:** 按 §0.5 的原生能力标注，由用户在 Chaos Studio 中先执行已确认能力的单 Action 测试。不再为本轮原生执行搭建自定义 canary、observer Job、SDK 流量或业务账本；暂不具备能力的场景明确标注并暂缓，不用模拟冒充原生测试。实际订单/库存/cache-aside 等业务验收保留给后续阶段。

### Navigation

- [统一范围、用例模板与用户场景映射](#0-unified-case-standard-and-current-campaign)
- [Boundaries](#1-recommendation-and-boundaries)
- [Current coverage and ownership](#2-current-coverage-evidence-and-ownership)
- [Workloads and measurable acceptance](#3-workload-and-measurement-design)
- [Common client-path cases](#4-common-client-path-cases)
- [Service and compute cases](#5-service-specific-test-cases)
- [Business-flow extension](#6-end-to-end-extension-after-individual-services-pass)
- [Authorization, stop and recovery](#7-safety-permissions-stopping-and-restoration)
- [Implementation tasks and waves](#8-dependency-ordered-delivery-and-execution-waves)
- [Evidence and verdicts](#9-evidence-and-result-classification)
- [Decisions and completion checklist](#10-decisions-and-completion-checklist)

## 0. Unified case standard and current campaign

### 0.1 本轮范围与状态

| 类别 | 本轮选择与约束 |
| --- | --- |
| VM | 可规划使用目前承载 RocketMQ 的 VM；仅做 V-03–V-10 基础设施验证。执行前确认其所有服务/消费者、允许中断、备份与恢复；不默认停止 broker、删除 broker 数据或杀 broker 进程。jumpserver/恢复 VM 永久排除。 |
| AKS | K-01–K-06 与 N-02–N-07 为候选；精确 namespace AND labels、测试 User pool/实际实例。System pool、恢复/验证组件排除；托管节点组通过 AKS 属性发现，不导入 VMSS、不接管节点生命周期。N-01 整个 zone 范围不是单实例授权。 |
| PaaS | C-01–C-05 按产品/协议拆变体；M-01/M-02/M-04、P-01/P-02、R-01–R-04、A-01/A-02、S-01–S-04、B-01–B-04、H-01–H-06 为资格待核候选，选中不等于可执行。 |
| 独立专项 | M-03/P-03 PITR、A-03/A-04 geo/topology、B-05 regional、N-01 zone-loss 保留；范围、资源生命周期或数据风险扩大时另审，不默认进入本轮。 |
| 不选/后续 | D-01/D-02 Cosmos 本轮不选；V-01/V-02 RocketMQ 业务验收不选；E-01–E-03 和各服务的业务 SLO 后续接入；L-01–L-03/G-01–G-03 无本轮目标，Future。I-01 为原生机制未映射、mesh 目标待核验，不据此认定平台不支持。 |
| 实际资源边界 | 真实资源组名、订阅/tenant、端点、VM/VMSS/node IDs、实体名只保存在私有 manifest；公开示例使用占位符。本轮同资源组目标及唯一 AKS 节点组例外须每次核对。 |

**选择、能力、准备、授权与运行结果分开记录：** Candidate 表示待资格核实，Future 表示未来补充，Unselected 表示本轮不选。未配置、缺目标、缺前置、缺证据、待授权不是同一种 Blocked；按下表记录准备状态。只有实际运行后才可给出 Passed/Failed/Inconclusive。目前本清单不宣称任何故障已通过。

| 准备状态 | 判定与后续动作 |
| --- | --- |
| PendingConfiguration / 待配置 | 已有相应原生能力，尚未创建明确目标配置；准备配置，不增加业务 SDK/自定义应用门槛。 |
| AwaitingTarget / 待选择目标 | 尚未选定符合 namespace/labels、实体或实例边界的已有目标；不把历史空 namespace 当当前永久阻塞。 |
| PendingPrerequisite / 待补前置 | 明确可补的身份、权限、安装或恢复前置尚未完成；记录缺项及 owning state，不默认扩大权限或改变共享资源。 |
| PendingVerification / 待核验 | 支持、连通、实际匹配、容量或恢复证据未核验；缺证据不等于证实不支持，也不等于就绪。 |
| PendingDesign / 待确认机制 | 当前精确故障语义或单实例作用边界尚未映射；标明“当前未确认等价原生 Action”，不使用不同故障冒充。 |
| PendingValidation / 待原生验证 | 配置已经部署，尚未通过原生 Validate 或存在需定位的 validation errors。 |
| Validated / 原生验证通过 | 当前配置原生 Validate 为 `Succeeded` 且解析到明确获批资源；仍须运行前重查动态目标、健康、影响、停止恢复与授权。 |
| AwaitingAuthorization / 待执行授权 | 机制可用，但 destructive/forced/扩大范围或恢复生命周期需要独立授权；配置存在不是执行授权。 |
| Blocked / 已证实阻塞 | 当前实际 SKU、拓扑或已复现失败与必要能力不兼容，并附具体证据；只阻塞该 variant，不阻塞其它可执行项。 |

原生能力另记“已确认 / 当前未映射 / 当前目标不兼容”，授权另记范围与恢复许可；可同时有多个准备缺项。未运行记 `execution=NotRun`，不填 Passed，也不因普通待办将整个 campaign 标为 Blocked。已有完整 infra/business runner 的前置拒绝逻辑不变；本表不是放宽其安全门槛或修改其结果枚举。

前次私有只读规划记录：MySQL 为 ZoneRedundant/Healthy，PostgreSQL 为 SameZone/Healthy；Storage 为 ZRS，不符合 regional planned failover 的 geo 前置；Service Bus Premium、Event Hubs Standard；AKS System/User pool 各两节点、声明三 zones，不证明实际放置。前次 authenticated readiness 为 4/4 nodes、6/6 Chaos 控制 pods Ready，target workloads 为空、verification namespace 不存在，临时身份/工具已清理。这些均是前次证据，运行前重验；HA、Ready、SKU 和静态测试不是故障验收。

### 0.2 每个用例的标准记录

§4–§6 的完整 infra/business 验收继承本模板、§0.3 的技术验证、§7 的停止恢复及 §9 的证据契约。当前先按 §0.5 执行原生 Action，完整技术/业务验收不作为该阶段的额外前置；原生运行结果与完整用例结论分开记录。

| 必填项 | 规范 |
| --- | --- |
| Case ID / variant / phase | 稳定编号；variant 明确产品、协议、planned/forced、topic/subscription 等；phase 为 `infra` 或 `business`。每个 variant 单独运行、单独结论。 |
| 目的与假设 | 预期受损对象、技术/业务行为、最大影响与恢复目标；可观测、可判定。 |
| 前置条件 | 当前 region/SKU/HA/agent/extension、健康/保护、身份/权限、目标/间接消费者、独立控制、容量、预算与停止恢复授权；缺项按 §0.1 标记待办，不执行。已证实技术不兼容才记 Blocked。 |
| 故障机制 | Workspace service-direct、AKS extension、agent、client-path simulation、service-native drill；完整 Action/API/version/schema。无支持不得猜 ID 或自动回退 classic/Chaos Mesh。 |
| 参数与范围 | 明确资源/实例/实体/namespace AND labels、实际匹配数、强度/持续时间、截止时间、排除项；禁止空/wildcard。动作 duration 不等于真实 outage/RTO。 |
| 基线与步骤 | §7.1 标准执行流程，记录无故障基线、真实注入、实际影响、告警、停止和恢复。 |
| 停止与恢复 | 每条阈值对应真实 observer/检测预算/operator；区分 Cancelable/Continuous 与不可逆 Discrete。记录原状态，只清理本次 owned 对象。 |
| 验收与报告 | 按 phase 检查真实影响、containment、技术完整性/业务不变量与逐窗口恢复；记录证据/hash/限制及中文结果，缺证据不写 Passed。 |

### 0.3 Infra-first 技术验证与 HA 前置

完整 `phase=infra` 的技术验收采用下表；当前原生先行阶段采用 §0.5，不以新建技术探针/SDK 流量/账本阻塞原生执行。§3 和原用例中涉及订单、库存、cache-aside/outbox、业务 SLO 的要求保留给 `phase=business`。报告必须区分原生 Action 结果、infra 验收与 business 验收：原生 `Succeeded` 不表示这两类完整验收已通过。技术探针/SDK traffic 也不能称为真实应用流量。

| 对象 | 基线、故障期间与恢复后的必要技术证据 |
| --- | --- |
| VM | Azure/guest health、CPU/memory/disk/IO、指定测试进程生命周期、真实目的地址连接；实际达到注入目标，非目标/恢复通道健康，压力/文件/网络规则无残留。VM Running 不能替代 guest readiness。 |
| AKS | 原/新 Pod UID、node/instance 映射、Ready/events/lease、requests/limits、真实副本/zone 放置、剩余容量、存储约束；验证受损与恢复，不用“新 Pod 存在”替代服务/协议恢复。 |
| MySQL / PostgreSQL | 有限唯一 ID 的测试事务写/读、attempt/ack/unknown 账本、已确认数据、连接恢复、HA 健康/角色；未知 commit 先查后判，不盲重发。SameZone HA 不证明 zone-loss。 |
| 两种 Redis | 独立测试 keys 的读写/版本、连接/拓扑、实际副本/HA；flush 仅完全独占可重建数据库并确认所有 geo links。不得承诺 cache writes 的通用零丢失。 |
| Blob | operation ID、hash、length、ETag/version、ack/unknown、实际保护/恢复；测试 prefix 与 backend/evidence/backup account 分离。 |
| Service Bus | 专用 queue/topic/subscription，有限 publish/PeekLock/settlement、producer ack/unknown、重复尝试与唯一技术 effect、outstanding/DLQ；恢复原实体状态，不称技术 effect 为业务交易验收。 |
| Event Hubs | 专用 hub/group、partition/sequence/offset、ack/unknown、独立 durable checkpoint、lag/retention 与 replay；没有全局顺序或平台 exactly-once/DLQ 承诺。 |

HA/控制资源配置是独立 Terraform 前置变更：在原 owning state 审查产品 HA/geo 差异、SKU/region/保护、成本及 delete/replace/migration 风险，不全量重建、不改 backend、不把同一资源写入第二 state。ZRS 不是 GRS/GZRS；Geo-DR 不是 Geo-Replication；HA standby 不是独立控制依赖。

Client-only 故障可共享**没有被故障操作**的服务，前提是实测 control path 不受影响；service/account/namespace 级故障须不同独立依赖和恢复路径。同一故障服务上的另一个 queue/container 或 standby 不能证明实例级 containment。现有 reference runner 的更严格 control 配置门槛仍须满足，本文不会自动放宽代码。

技术参数是待确认建议，不是服务 SLA：初始网络 +100 ms/1% loss、60 秒；Pod 保留当前 25%/60 秒/CPU 1–2 cores/memory 1–128 MB/loss 1–10%/latency 1–500 ms guards；实际百分比取整先核对。VM/node CPU 从 50% 逐级，95–100%、memory 90%、disk exhaustion 仅专用可恢复目标后续单独审查，不照搬全 namespace、30% loss 或长时默认值。

基线与恢复建议每条技术路径每秒至少一个有效观测，记录样本数；恢复十个连续一分钟窗口达到约定 health/技术读写标准，control 每窗口无失败。observer stale 超过 15 秒、未授权目标/数据异常、System pool/恢复路径受损或超过实际匹配/成本预算即停止。压力目标本身的预期高 CPU 不套用非目标 80% 警戒。不同服务的 recovery budget、数据/消息量、TTL/retention、bytes/partition lag 上限在执行前确认；未确认不启动。

### 0.4 用户 39 个场景与规范编号映射

每一用户场景恰有一行映射；带产品后缀的是 C-family 的独立 variant。表中映射不代表已支持、已实施或已运行；资格以对应定义为准。

| 原场景 | 名称 | 规范编号 |
| --- | --- | --- |
| 4.1.1 | VM CPU 满载 | V-03 |
| 4.1.2 | VM memory 满载 | V-04 |
| 4.1.3 | VM 网络延时 | V-05 |
| 4.1.4 | VM 网络丢包 | V-06 |
| 4.1.5 | VM 磁盘满载 | V-07 |
| 4.1.6 | VM 磁盘 IO 压力 | V-08 |
| 4.1.7 | VM 重启 | V-09；不替代 V-01 broker 业务验收 |
| 4.1.8 | VM 应用进程终止 | V-10 |
| 4.2.1 | AKS Pod 意外终止 | K-01 |
| 4.2.2 | AKS Pod CPU 满载 | K-02 |
| 4.2.3 | AKS Pod 内存泄漏 | K-03 资源压力 / K-06 逐步增长模拟，分别验收 |
| 4.2.4 | AKS Pod 网络丢包 | K-05 |
| 4.2.5 | AKS Pod 网络延时 | K-04 |
| 4.2.6 | AKS 节点 CPU 满载 | N-02 |
| 4.2.7 | AKS 节点内存满载 | N-03 |
| 4.2.8 | AKS 节点网络丢包 | N-04 |
| 4.2.9 | AKS 节点网络延时 | N-05 |
| 4.2.10 | ASM 控制层/数据层断连 | I-01 |
| 4.2.11 | AKS API Server/节点断连 | N-06 |
| 4.3.1 | MySQL HA 故障转移 | M-01 |
| 4.3.2 | MySQL 重启 | M-02 |
| 4.3.3 | MySQL 网络中断 | C-01.mysql |
| 4.3.4 | MySQL read replica 不可用 | M-04 |
| 4.4.1 | Storage 网络不可达 | C-01.blob / C-04.blob，分别连接/DNS模拟 |
| 4.4.2 | Blob 误删与恢复 | S-04 |
| 4.4.3 | Storage 区域故障转移 | S-03，planned，不是实际 region outage |
| 4.5.1 | Legacy Redis 网络不可达 | C-01.legacy-redis / C-04.legacy-redis |
| 4.5.2 | Legacy Redis primary reboot/倒换 | R-01 |
| 4.5.3 | Legacy Redis replica reboot | R-02 |
| 4.5.4 | Legacy Redis 全数据库 flush | R-04；不替代 R-03 有限 key invalidate |
| 4.6.1 | Event Hubs 网络不可达 | C-01.event-hubs / C-04.event-hubs；不替代 H-01/H-02 entity state |
| 4.6.2 | Event Hubs 消费积压 | H-04 |
| 4.6.3 | Event Hubs 跨区域倒换 | H-05 metadata Geo-DR / H-06 data Geo-Replication，分别验收 |
| 4.7.1 | LB 单 backend 故障 | L-01，Future |
| 4.7.2 | LB backend 网络中断 | L-02，Future |
| 4.7.3 | LB backend probe 异常 | L-03，Future |
| 4.8.1 | Application Gateway 单 backend 故障 | G-01，Future |
| 4.8.2 | Application Gateway backend 网络中断 | G-02，Future |
| 4.8.3 | Application Gateway backend probe 异常 | G-03，Future |

PostgreSQL、Managed Redis、Service Bus 原用例完整保留；另补 N-07 单测试节点不可用。**禁止旧步骤照搬：** 不删共享 Private DNS A record、不改共享 NSG/SAS Listen、不启用 Redis access keys、不全盘填满、不按名字批量 kill、不默认安装 Chaos Mesh。无等价原生 Action 的模拟/native drill 必须显式分类，不声称 Azure 服务真实 outage。

### 0.5 原生能力优先：本轮执行与暂缓标注

**最新执行分工：依据用户本次“先用原生能力测试并生成报告”的要求，助手执行通过实时核验的既有单目标 PaaS 配置，并收集原生运行/管理面恢复证据。** 本轮按 M-01/M-02/P-01/R-01/R-02/B-01/B-02/H-01/H-02 分别核验、串行执行；Action duration 为1分钟，不等于真实中断时长。每次要求目标/参数/排除一致、最新 Validate 成功、无其它运行、健康与恢复可核验。目标越界、15分钟运行超时或10分钟恢复超时即停止；可取消动作先取消，再仅恢复本次消息实体到原 Active 状态，不盲重发 Execute。P-02 forced、VM/节点中断、flush/unlink 不随普通测试请求自动执行。保持 private AKS，不新建自定义应用/observer、不安装 Chaos Mesh、不补 guest 模拟、不通过 Terraform 启动故障。此前“用户自行 Execute”和“未启动故障”是准备阶段的历史记录，不能覆盖本次实际运行证据。

**最新实际结果：** 2026-11-23 已执行上述9项原生测试，9个 run / Action 均 Succeeded，7项管理面状态变化/恢复已观察；Redis 两项缺独立节点影响证据，影响结论为 Inconclusive。五个目标最终 Resource Health Available，数据库 Ready / HA Healthy、消息实体 Active，无活动运行，private AKS 保持不变。MySQL 查询超时断档与 PostgreSQL 首次收尾 Resource Health Unavailable 后恢复均如实保留，没有重复 Execute。完整 infra/business 未验证；详见[原生测试报告](./chaos-studio-native-test-report.md)。下方是能力/准备记录，不是把70项全部判 Passed。

2026-11-23 初次核对：Workspace provisioning 为 `Succeeded`，有 **25 个推荐 Scenario**，但资源发现为 **0**，检查的 MySQL 推荐模板运行 Configuration 为 **0**。Reader grant 与 scope 已存在，缺少显式原生资源发现；不是缺少 SDK 或 private AKS 需要开放公网。

**首批已实施（历史基线）：** 对获批资源组调用原生 `discover` 后，发现 **57 个资源**，包括 private AKS 和所需 PaaS。使用原有 Chaos state 新增 **10 个单 Action Scenarios + 10 个明确单目标 Configurations**，绑定 MySQL、PostgreSQL、Legacy Redis、Service Bus、Event Hubs 及私有 RocketMQ VM 六个已有资源；新增六个 target-only custom roles 及其 assignments。两批各16 create，已有资源 update/delete/replace 为 **0**，没有启动故障。57 个发现资源不等于57个授权故障目标；每个配置只允许一个明确实例/namespace，消息实体进一步限定为已有的一个明确 queue/hub。jumpserver 不在任何配置目标中。

自动推荐库仍保留。MySQL 推荐模板包含 Azure Load Testing，部分其它模板同时包含 VMSS/数据库/runbook 等多个 Actions，不直接整套执行；使用独立创建的单故障配置。名称为 `m01-mysql-ha-failover`、`m02-mysql-restart`、`p01-postgresql-planned-failover`、`r01-legacy-redis-primary-reboot`、`r02-legacy-redis-secondary-reboot`、`b01-servicebus-send-disabled`、`b02-servicebus-receive-disabled`、`h01-eventhub-send-disabled`、`h02-eventhub-disabled`、`v09-private-vm-restart`，各 Configuration 名称为 `approved-targets`。**10/10 原生 validation 已 `Succeeded`，且各实际解析到唯一指定目标。** 目标标识、完整参数、授权及 validation 证据保留私有。

**本轮修复错误阻塞并补齐配置：** ARM 实例级核验确认 User pool 两个运行中实例分别处于 zone 2、3，System pool 另有两个运行中实例。新增 `n07-single-user-node-shutdown`，只选明确 User VMSS、其实际 region 和当前恰有一个实例的 zone 2；持续1分钟，`GracefulShutdown=true`，全部配置显式排除 System VMSS。只追加由 AKS `nodeResourceGroup` 属性发现的既定节点组例外及该 User VMSS 的 target-only 权限，不导入/修改节点生命周期，不需要访问 private Kubernetes API。单节点仍损失当前 User pool 一半容量，运行前必须重查匹配数、实际 workload 放置和剩余容量，autoscaler 后不得沿用旧快照。

同时新增 `p02-postgresql-forced-failover`，复用已绑定服务器与已有 target-only 权限，模式为 `ForcedFailover`；执行与恢复风险另审。现有十项原生 Action/目标/参数不变。Saved plan 共 **7 create、11 metadata update、0 delete/replace**：4个 Scenario/Configuration、1个 User VMSS custom role/assignment、1个节点组 Reader assignment；更新仅为 Workspace discovery scope 和十个现有配置的 System VMSS 排除。刷新发现为 **69 个资源**，不是69个授权故障目标；当前共12项配置、7个明确目标资源。**12/12 原生 validation 均 `Succeeded`，各解析到唯一指定目标资源；相同完整输入 replan exit code 为0。** N-07 首次权限求值需等待新 Reader 传播，核对实际 assignment/principal/scope 后有限重验通过，没有扩大权限或调用权限自动修复。未启动故障。

另核对 [agent-based requirements](https://learn.microsoft.com/en-us/azure/chaos-studio/chaos-studio-scenarios#agent-based-scenario-requirements)：原生 VM CPU/内存压力会在运行时**自动安装 agent extension，结束后保留**，不需要先手工安装 classic agent。实际 VM 为受支持 Ubuntu 22.04，但当前没有 managed identity，且 public outbound 尚未核验；V-03/V-04 是可补前置/待核验，不是因为未预装 agent 而永久 Blocked。没有 inbound public IP 不证明 public outbound 不可用；也不能据此认定限制为仅私网的 agent 场景受支持。身份须由原 owning state 补齐，不能借用 Workspace identity 替代 VM identity，也不为测试开放私有网络。

下表覆盖全部 **70 个 Case ID**，能力与本轮是否就绪分开标注。依据为当前 Workspace 区域的完整 Action catalog、已安装推荐 Scenarios 和 [AKS extension 官方能力][aks-extension]；“未确认”只指当前 Workspaces/资源类型/故障语义，**不声称其他区域、classic 或其他产品永久不支持**。

| Case ID | Chaos Studio 原生能力 | 本轮标注 / 原因 |
| --- | --- | --- |
| M-01, M-02 | 有：MySQL HA failover、restart。 | **两项均已配置并绑定明确单服务器，原生 validation 均 `Succeeded`**。当前 HA 为 ZoneRedundant；两种故障分别运行，不把配置成功当故障通过。 |
| P-01, P-02 | 有：PostgreSQL planned/forced HA failover。 | **两项均为 Validated，P-02 执行仍为 AwaitingAuthorization**。复用已有单服务器/权限；当前 SameZone HA 不证明 zone-loss，forced 的影响/恢复仍需独立核对。 |
| R-01, R-02 | 有：Legacy Redis primary/secondary reboot。 | **两项均已配置并绑定明确单实例，原生 validation 均 `Succeeded`**。当前 Standard，单次一个角色；不是 Managed Redis reboot，不选 AllNodes。 |
| B-01, B-02, B-03 | 有：Service Bus queue/topic/subscription state。 | **B-01/B-02 已绑定一个明确已有 queue，原生 validation 均 `Succeeded`；B-03 暂未配置，需独立 topic/subscription 与 Discrete 恢复/配置 opt-in**。不得把 queue 结果替代 topic/subscription。 |
| H-01, H-02 | 有：Event Hub entity state。 | **已绑定一个明确已有 hub，原生 validation 均 `Succeeded`**；分别 `SendDisabled`/`Disabled`，不是区域故障或 queue ReceiveDisabled。 |
| V-09 | 有：单 VM restart。 | **已绑定已批准私有 RocketMQ VM，原生 validation `Succeeded`**；jumpserver 排除。运行前仍核对所有间接消费者的中断/恢复；重启不能取消/撤销，不代表 broker 业务验收。 |
| V-03, V-04 | 有：VM CPU/physical memory pressure；agent 由原生运行自动安装并保留。 | **PendingPrerequisite / PendingVerification**：Ubuntu 22.04 合格；VM managed identity 缺失，public outbound、实际 headroom 与恢复待核验。不是“先手工装 agent”。保留默认关闭/单 VM/初始≤50% guards，不直接满载，不开放私有网络。 |
| K-01, K-02, K-03, K-04, K-05 | 有：AKS extension 的 Pod delete、CPU、memory、latency、loss。 | **AwaitingTarget / PendingVerification**：前次专用 namespace 无 workload Pod，仅为历史证据；需从私网操作端选择当前已有获授权 namespace AND labels 并核验匹配。extension 0.1.12 已安装；private AKS 官方未验证，不是声明不支持。只短时验证，不新建自定义应用。 |
| N-01 | 有：VMSS shutdown；不是完整区域失效。 | **PendingConfiguration / AwaitingAuthorization**：实际 zone 已核验，但本项扩大到整个获批 zone 范围；不能借 N-07 单节点授权执行。容量/workload 放置仍须运行前重查。 |
| N-07 | 有：VMSS shutdown，通过实际单实例 zone 限定。 | **Validated**：一个明确 User VMSS、region、zone 2 当前恰有一个 running 实例；System VMSS 明确排除。运行前重查恰好一个实例及剩余一节点容量，不随机删实例，不把配置资源数当实例数。 |
| N-02, N-03 | catalog 有 VMSS CPU/memory pressure。 | **PendingDesign / PendingVerification**：当前模块只实现单 VM 压力，VMSS agent 的精确实例作用边界、身份/出站与 headroom 待确认；不压整池，不用 Pod hog 替代，不因缺实现称平台不支持。 |
| S-03 | 有：Storage planned account failover。 | **Blocked：当前 Standard_ZRS，不具备 geo failover 前置**；不为补齐测试改成 GRS/GZRS。 |
| A-02 | 有：Managed Redis flush database。 | **PendingVerification / AwaitingAuthorization**：当前数据库无 geo links，但独占/可重建性及删除恢复仍待确认；属于不可撤销数据删除，不默认配置/执行。不能以未知数据性质判永久 Blocked。 |
| A-04 | 有：Managed Redis force-unlink。 | **Blocked：实际数据库没有 geo-replication links，无可 unlink 的对象**；这是已证实当前拓扑缺项，不是缺 SDK。需要另行批准 geo topology/恢复生命周期后重评，不自动创建第二实例。 |
| C-01, C-02, C-03, C-04, C-05 | 当前未确认与单依赖连接/延迟/未知确认/DNS/throttle 语义等价的原生 Action。 | **暂不具备本轮原生执行能力**；Pod-wide network 或共享 NSG 修改不等价；不搭 proxy/hook 模拟补齐。 |
| M-04 | 未确认独立 read replica 不可用的对应原生 Action。 | **暂不具备能力，且独立 replica 目标未证实**；HA standby 不替代 read replica。 |
| R-03, R-04 | 未确认 Legacy Redis 有限 key invalidation / 全库 flush 的对应 Workspace Action。 | **暂不具备 Chaos Studio 原生能力**；Redis data-plane expire/flush 是另行评审的服务原生操作，不套 Managed Redis Action。 |
| A-01, A-03 | 未确认 Managed Redis 单客户端断连/区域客户端重定向的等价原生 Action。 | **暂不具备本轮原生执行能力**；不把 flush/unlink 冒充断连、reboot 或区域丢失。 |
| S-01, S-02 | 未确认 Blob interrupted-transfer/客户端 secondary-read fallback 的等价原生 Action。 | **暂不具备本轮原生执行能力**；当前 ZRS 也没有 RA-GRS/RA-GZRS secondary-read 前置。 |
| B-04, H-03, H-04 | 未确认 commit/settlement/checkpoint 间隙或专用 consumer pause 的等价原生 Action。 | **暂不具备本轮原生执行能力**；状态禁用和 Pod 删除不能直接证明这些事务时序/积压语义。 |
| K-06 | 固定 Pod memory hog 存在；没有已确认的逐步内存泄漏模型。 | **暂不具备对应原生能力**；K-03 不等价于 K-06，不编写增长进程补齐。 |
| V-05, V-06, V-07, V-08, V-10 | 当前未确认 VM 精确目的路径 latency/loss、专用卷 exhaustion/IO、指定 guest 进程终止的对应 Workspace Action。 | **暂不具备本轮原生执行能力**；不回退 classic、不安装 guest 模拟；App Service kill-process 不适用于 VM。 |
| N-04, N-05, N-06 | 当前未确认精确单 node 网络 loss/latency/API partition 的对应 Workspace Action。 | **暂不具备本轮原生执行能力**；Pod-only 故障不证明 node-wide，禁止修改共享 NSG/API 路由。 |
| I-01 | 未确认 ASM/Istio control/data partition 的对应原生 Action。 | **PendingDesign / AwaitingTarget**：当前未确认精确机制/已有 mesh 目标；明确暂不具备本轮等价原生执行能力，不判平台永久不支持，不为此安装 mesh。 |
| M-03, P-03, S-04, B-05, H-05, H-06 | 服务原生 PITR/Blob protection/Geo-DR 或 Geo-Replication 操作；不是本轮已确认的 Chaos Studio Action。 | **服务原生专项，暂缓**；需要独立恢复/geo 前置及生命周期授权，不记作 Chaos Studio 原生故障通过。 |
| D-01, D-02 | D-02 catalog 有 Cosmos offline-region；D-01 客户端模拟未确认等价 Action。 | **Unselected：Cosmos 本轮不选**；不是必须补齐的 Failed/Passed 项。 |
| V-01, V-02 | VM restart/pressure 可提供故障机制，但不能验证 broker durability。 | **Unselected：RocketMQ 业务本轮不选**；仅 V-03–V-10 对应基础设施范围仍按本表处理。 |
| L-01, L-02, L-03, G-01, G-02, G-03 | catalog 有 LB backend admin-state；其余精确网络/probe/Gateway 故障未确认等价 Action。 | **Future：本轮无获授权 LB/Gateway 目标**；不动 AKS 托管 LB、不创建新 Gateway。 |
| E-01, E-02, E-03 | 原生 Action 可提供部分依赖故障；不能自动证明完整业务流程。 | **Deferred：业务验收后续实施**；不作为当前原生测试前置。 |

**原生执行最短流程：**

1. 进入现有 **Workspace 的发现资源与 Scenario Configuration**，不是 Experiments (classic) 的 Targets/capabilities。选择上表已通过原生 validation 的单故障配置；核对资源当前健康、参数/影响上限、停止条件与恢复措施。推荐先 M-02 或已有明确 queue 的 B-01/B-02，不同时故障多个资源。
2. 在 Portal 创建/选择单 Action Scenario 与 Configuration，显式限定目标，不使用空筛选器。新 operator-owned 配置独立命名并登记 ownership；不改 Terraform-owned Workspace，不全量 apply 基础设施/Chaos stack。核对 validation/权限，不自动提升权限或触发 `fixResourcePermissions`。
3. 用户显式 Execute。使用 Chaos Studio 原生 Scenario report，加 Azure Activity Log/已有 Azure Monitor 或 Kubernetes events 观察；不以新建 SDK/observer 为前置。持续观察停止阈值，按该 Action 是否可取消处理；Discrete 动作不能靠 Cancel 撤销。
4. 确认故障实际命中、原生运行状态、目标恢复及无残留。按原状态恢复 queue/topic/subscription 等；不默认第二次 failover/reboot。下一单故障必须等本次恢复。
5. 报告分列：`原生运行结果`、`实际命中/资源恢复证据`、`完整 infra/business 用例结果`。后者未验证就明确“未验证”；`Skipped`、零目标或无实际作用不能标 Passed。

原生 Execute/Validate/Cancel 路径已通过官方 `2026-08-01-preview` OpenAPI 核对：Configuration 的 `POST .../execute`、`POST .../validate` 均无请求 body；run 使用 `GET .../runs/{runId}` 和 `POST .../runs/{runId}/cancel`。仅供显式操作，不创建 Terraform run/provisioner，不猜测 `runs/start` API。

新 RBAC assignment 创建顺序不保证即时生效。初次 validation 的 `RequiresAttention` 必须检查具体缺失权限，与真实角色/作用域/identity 对照后只重试失败配置；不得自动授予 Contributor、重复扩大授权或把 HTTP 200 当 validation 成功。运行前需要该配置最新原生 validation 为 `Succeeded` 且实际解析到唯一获授权目标。

## 1. Recommendation and boundaries

Follow the [Well-Architected reliability testing guidance][waf], but declare the evidence level. The current infra-first campaign validates actual fault impact, technical integrity, containment and recovery using §0.3. The later business phase validates application flows, bounded retries/deadlines, graceful degradation and end-to-end invariants. Neither phase is accepted merely because Azure reports a successful Action.

Use three distinct mechanisms:

1. **Chaos Studio Workspaces / Scenarios:** supported service-direct Actions, after regional catalog, resource eligibility, identity, and API validation.
2. **Client-path simulation:** application test hooks or a protocol-aware fault proxy used only by selected test workloads in cloud AKS. This tests client resilience, not an actual Azure service outage.
3. **Service-native recovery drills:** backup restoration and regional promotion procedures not supplied by the selected Chaos Action.

Microsoft recommends Workspaces for new tests. Do not copy classic fault URNs, targets, or capabilities into Workspace Scenarios. Do not automatically fall back to classic when an Action is unavailable. See [Workspaces overview][workspaces] and [current Action catalog][catalog].

Mandatory containment boundaries; numerical exposure defaults remain proposals:

- Dedicated non-production targets and synthetic data; no production or shared infrastructure.
- One service and one fault at a time; no overlapping runs on the same target.
- One labeled application canary initially, plus an unaffected control canary.
- Explicit target allowlist, namespace, workload labels, entity names, and destination endpoints.
- No fault-time modification of shared DNS, NSGs, private endpoints or node-pool lifecycle. Necessary HA/control prerequisites are separately planned in their owning state and explicitly reviewed before deployment.
- No deployment, resource restart, scaling, flush, failover, or fault execution as part of this planning change.
- Approval of this document permits planning only. Deployment and execution require separate authorization.

Canary selection limits test traffic, not the blast radius of a service-direct Action. A restart/failover/entity disable can affect other clients using that target. Follow the case-aware independent-control boundary in §0.3; a control client sharing a faulted service cannot establish instance-level containment. Enumerate indirect consumers and geo-linked members before authorization, including processes on the VM chosen for infra tests.

## 2. Current coverage, evidence and ownership

### 2.1 Evidence levels and current baseline

Coverage has four independent levels: **declared configuration**, **installed/usable infrastructure**, **qualified fault impact**, and **accepted business recovery**. A module, mock pass, Ready pod, recommended Scenario, or no-drift plan cannot substitute for the next level.

This review inspected the working tree and official documentation, not live Azure, state, saved plans, or private inputs. The installation statements below are **recorded prior evidence** from the [deployment runbook](./terraform-deployment-runbook.md), not newly repeated checks. Reconfirm them before a run. Uncommitted measurement/stop work is provisional, not a delivered runtime capability.

| Area | Current source / recorded evidence | Remaining qualification |
| --- | --- | --- |
| Platform and AKS | [Root](../main.tf) owns the RG and wires private AKS/networking. Installation records private AKS, OIDC, Workload Identity and Azure RBAC. | Reference existing ownership/state; verify real canary/control placement, capacity, private DNS and authenticated access. No platform recreation. |
| PaaS fixtures | [Fixture wiring](../fixtures.tf) includes MySQL, PostgreSQL, Managed Redis, legacy Redis, Event Hubs, Service Bus and Storage. Root defaults and environment profiles differ. | Module presence is not deployment/eligibility proof. Confirm selected resources, credentials/data grants, HA and protocols privately. |
| Cosmos DB | [Module](../modules/cosmosdb/) exists; the documented dev profile disables account creation while retaining existing network/naming resources. | Optional existing eligible target or a separately costed fixture; no mandatory account creation to fill a matrix. |
| RocketMQ | [VM module](../modules/vm/) and runbook describe pinned native bootstrap on a private VM. | Prove actual NameServer/Broker readiness, persistence, delivery contract and business effects. VM readiness alone is insufficient. Exclude jump/recovery hosts. |
| Workspace and configuration | [Chaos module](../modules/chaos/) and [stack](../stacks/chaos/) declare a UAMI, RG-scoped discovery, target permissions and bounded single-Action configurations. Creation defaults off; no run/schedule resource. | Exact regional schemas, parameters, discovered/excluded lists and usable runtime permissions per selected case. Existing-Workspace reference mode is not implemented; do not create over an externally owned Workspace. |
| AKS extension | Prior installation records version 0.1.12, auto-upgrade off, subscriber federation/connection trust, cluster operator grant, two Deployments 1/1 and DaemonSet 4/4 Ready. Target namespace had no workload pods. | Installation is not private-cluster functional qualification. Preview actual targets and prove a separately authorized fault. `Pending` connection status is a known issue, neither failure nor readiness proof. |
| Scenario library | Prior records: 25 recommended Scenarios, zero configurations, no fault/verification Job run; post-extension Chaos plan exit 0. | Recommendations are service-populated, not implemented cases or runs. Counts can change with discovery; do not delete the library to achieve zero. |
| Pod configuration | [Pod definitions](../modules/chaos/pods.tf) reference an external installation and implement five bounded Actions. | Compatibility flags are evidence assertions, not bypass switches. Namespace, architecture, image tools, admission and network cleanup require per-case verification. |
| Measurement and stop | [Verification module](../modules/chaos-validation/) provides restricted, opt-in finite phased HTTPS Jobs, streaming evidence and an availability stop evaluator. Follow-up code adds bounded Blob/Service Bus reference clients, a crash-safe synthetic operation/effect ledger, private manifest gates and recorded recovery-window checks. | Real application flows, other protocol clients, qualified independent ledger storage, service/integrity observers and monitor deployment/notification remain incomplete. Scripts are packaged, but the declared Job still runs `probe.py`; no reference traffic or fault is started by packaging. |
| Monitoring, policy and tests | [Monitoring](../modules/monitoring/), [focused tests](../tests/) and [validation-only CI](../.github/workflows/terraform-validation.yml) exist. | Historical counts are not a fresh result. Confirm selected metrics/alerts, policy applicability, current checks and private evidence retention. |
| Supporting components | [Cluster stage](../stacks/cluster/) offers opt-in ingress/GitOps; recorded Chaos onboarding leaves them disabled. | No ingress/Argo CD required solely for Chaos. ACR, DNS, monitoring, backend, backup and recovery components are excluded from faults by default. AGFC is not an Azure Load Balancer Action target. |

The reviewed toolchain is CLI **1.15.6** (CI/runbook), AzureRM **4.55.0**, AzAPI **2.14.0**, Random **3.7.2**, and cluster providers Kubernetes **2.38.0** / Helm **2.17.0**. [Root constraints](../version.tf) permit Terraform `>=1.9,<2.0`; this is not an exact executable pin. Respect each stage's lockfile and existing module-test override practice. Do not upgrade providers or change backends as part of this consolidation.

Original findings about absent modules/CI/Workspaces, AzureRM 3.115.0/AzAPI 2.7.0 and failed provider downloads are superseded as current inventory. Historical test/lint/scan counts remain historical, including unresolved policy applicability; this review neither re-ran them nor declared them resolved. Earlier RG, network, credential, naming and interface changes still require state-specific migration scrutiny on any older environment.

**2026-11-23 implementation follow-up:** Cloud testing was conditionally authorized after readiness; this is separate from documentation approval and does not authorize new destructive/shared-lifecycle changes. Bootstrap received a verified official AzAPI `h1:` checksum only, without a version/state change. Reference clients and ledger/manifest checks remain offline evidence. Later temporary managed-identity access proved authenticated private AKS readiness; all temporary IAM/guest assets were removed and original VM identity restored. Requalify access and targets before any run. Earlier environment migration risks remain independently reviewed; §0 is the current campaign selection, not a full-matrix success claim.

### 2.2 Ownership and Terraform contract

| Owner | Resources / responsibility | Boundary |
| --- | --- | --- |
| Platform state | RG, AKS/VNet/ACR, selected PaaS/VM fixtures and bounded monitoring | Preserve existing inputs, addresses and deployed resources; disabling an already-enabled component can delete it. |
| Cluster state | Optional controller/GitOps and verification namespace, scripts and explicitly approved Jobs | Independently authenticate to existing private AKS; Job creation runs traffic and needs approval even with no Chaos fault. |
| Chaos state | Workspace/UAMI, discovery grants, reviewed service-direct permissions and Scenarios/configurations | Configuration only. One stable-key case per initial configuration; no provisioner/run/scheduler. |
| Operator installation | AKS extension, subscriber identity/federation, connection and built-in cluster operator grant | Reference, do not duplicate. Adoption requires an explicit ownership/import plan. |
| Recovery operator | Fault stopping/removal, native restoration and evidence collection | Separately authorized actions; no default fault-start privileges on application or verification identities. |

Use separate environment/stage state paths or backend keys and identities. tfvars and CLI workspace names are not isolation. The root currently defaults to local state; protect it and prevent divergent copies/concurrent writers. Team/cloud deployment should use independently bootstrapped, protected Entra-authenticated remote state under the runbook's separately approved migration. Never fault backend/evidence/backup storage or use empty state, `state rm`, force-unlock or destroy to hide drift.

Preserve the [Chaos input contract](../modules/chaos/README.md):

- Explicit dev/test metadata, RG discovery scopes, exact target IDs and production/shared/recovery exclusions.
- Verified case-sensitive Action parameters, required entity names and JSON-array encoding for `queues`, `topics`, `subscriptions`, `eventhubs` and linked database IDs. Regional schema confirmation is still required.
- Service-direct structural durations currently allow whole minutes **1-5**. The ARM schema requires `duration` even for Discrete Actions; it is not their outage duration or rollback promise.
- Pod effects currently cap at **60 seconds**, affected pods at **25%**, CPU at **1-2 cores**, memory at **1-128 megabytes** (`memoryConsumptionMegabytes`), latency at **1-500 ms**, packet loss at **1-10%**. Use the minimum practical effect first; do not relax code guards merely to match a proposed later wave.
- Namespace membership must match installation; exact AND-matched labels include `chaos-canary=target`. Empty/wildcard selectors and default/system/control/verification namespaces are forbidden.
- Destructive-configuration opt-in is not execution permission. The code's destructive list is not a complete operational risk classification: DB forced failover, all-node reboot, pod deletion and node shutdown also need explicit impact/recovery review.
- Discovery Reader access is separate from Action rights. Custom role definitions are RG-scoped, but assignments stay on exact service targets; the installer owns the distinct cluster-level pod operator grant. Never grant subscription Owner/Contributor or auto-repair permissions.

For `2026-08-01-preview`, use `resourceTargeting`, not mixed legacy `filters`/`exclusions`. Values within one include category are OR; non-empty categories combine with AND; exclusion wins. This is **not** the pod label AND contract. Empty/missing criteria do not restrict discovery. Require exact resource IDs and compare resolved/excluded resources with the private allowlist before each run. Preserve parameters during any configuration update; older CLI configuration commands use a different API model.

### 2.3 Current service-direct support

The following identifiers and semantics are from the [Workspaces Action catalog][catalog]. Listed support is **not** proof of availability or eligibility in the user's subscription.

| Service / resource type | Action ID | Semantics and eligibility checks |
| --- | --- | --- |
| MySQL / `Microsoft.DBforMySQL/flexibleServers` | `microsoft-mysql-failover/1.0` | Cancelable; required `RestoreOnStop`. Confirm healthy eligible HA server. Restoring the original primary is an attempted operation, not a guaranteed rollback. |
| MySQL / same type | `microsoft-mysql-restart/1.0` | Discrete; one restart, no automatic undo. |
| PostgreSQL / `Microsoft.DBforPostgreSQL/flexibleServers` | `microsoft-azurepostgresql-failover/1.0` | Cancelable; required `FailoverMode`: `PlannedFailover` or `ForcedFailover`. `RestoreOnStop` and `SkipIneligibleServers` are optional. Read replicas and non-HA servers are ineligible. |
| Azure Cache for Redis / `Microsoft.Cache/redis` | `microsoft-azureclusteredcacheforredis-reboot/1.0` | Discrete; `RebootType`: `PrimaryNode`, `SecondaryNode`, or `AllNodes`. Use an explicit `ShardId` only for clustered caches. Not the Managed Redis reboot mechanism. |
| Managed Redis / `Microsoft.Cache/redisEnterprise` | `microsoft-managedredis-flushdatabase/1.0` | Discrete; `DatabaseName`. Destructive: a geo-linked flush can remove all data from ALL linked caches. |
| Managed Redis / same type | `microsoft-managedredis-forceunlink/1.0` | Discrete; `DatabaseName`, `LinkedDatabaseResourceIds`. Changes replication topology; no automatic re-link/undo. |
| Storage / `Microsoft.Storage/storageAccounts` | `microsoft-storageaccount-plannedfailover/1.0` | Discrete; account-wide, not container-scoped. Requires eligible geo-redundancy, completed initial synchronization, and both regions available. |
| Service Bus / `Microsoft.ServiceBus/namespaces` | `microsoft-servicebus-changequeuestate/1.0` | Cancelable; required `desiredState`: `Active`, `Disabled`, `SendDisabled`, or `ReceiveDisabled`; explicit `queues`. |
| Service Bus / same type | `microsoft-servicebus-changesubscriptionstate/1.0` | Discrete; required `topic`, `subscriptions`, `desiredState` (`Active` or `Disabled`). Explicit recovery is required. |
| Service Bus / same type | `microsoft-servicebus-changetopicstate/1.0` | Discrete; required `topics`, `desiredState` (`Active` or `Disabled`). Explicit recovery is required. |
| Event Hubs / `Microsoft.EventHub/namespaces` | `microsoft-eventhub-changeeventhubstate/1.0` | Cancelable; `desiredState`: `Active`, `Disabled`, `SendDisabled`; explicit `eventhubs`. No queue `ReceiveDisabled` value. |
| Cosmos DB / `Microsoft.DocumentDB/databaseAccounts` | `microsoft-documentdb-offlineregion/1.0` | Cancelable; required `RegionName` is a display name, not a normalized location filter. Confirm API/topology eligibility and recovery; single-region defaults are insufficient. |
| VM / `Microsoft.Compute/virtualMachines` | `microsoft-compute-restart/1.0` | Discrete; VM restart, not a proven broker recovery. Exclude management/recovery VMs. |
| VMSS / `Microsoft.Compute/virtualMachineScaleSets` | `microsoft-virtualmachinescaleset-shutdown/1.0` | Cancelable; explicit `Zones` and reviewed `GracefulShutdown`. May affect every matching instance in a selected zone; not a single-node selector. |
| VM / qualified agent (VMSS catalog-only) | `microsoft-compute-cpuPressure/1.0` | Continuous; actual regional parameter `pressureLevel` 1–100 and required `duration`. Module derives duration, requires one agent-verified VM, and caps initial pressure at 50 unless separately opted in. No assumed single-VMSS-instance targeting. |
| VM / qualified agent (VMSS catalog-only) | `microsoft-compute-physicalMemoryPressure/1.0` | Continuous; `pressureLevel` 1–99 and required `duration`; same agent/ownership and default-low-pressure gates. Physical memory pressure is not a progressive leak. |

Before configuring a case, retrieve the Workspace region's full Action schema, verify parameter shapes, permissions, duration limits and target eligibility, and preserve the pinned `2026-08-01-preview` API. Official catalog presence and AzAPI schema acceptance are not subscription eligibility. Workspace and targets can be in different regions.

The module allowlists **14** service-direct Actions plus **2** bounded, agent-qualified single-VM pressure Actions, not every official compute Action. The UK South catalog and installed recommended Scenarios were queried read-only: pressure parameter names are lowercase/camelCase `pressureLevel` and `duration`; the table preserves the installed Scenario `actionId` casing rather than substituting a canonical URN. See the [single-VM pressure contract](../modules/chaos/README.md#optional-single-vm-pressure-definitions). This confirms regional schema, not guest eligibility or a successful run. Compute shutdown/redeploy/delete/hibernate variants are not interchangeable; VMSS pressure remains unimplemented pending exact-instance qualification. Any extension requires separate schema, ownership, safety tests and recovery qualification, never an automatic fallback to classic.

No direct Managed Redis reboot Action is listed in this catalog. Connection interruption is not evidence of a real node failover. Likewise, queue disable is not a Service Bus regional outage, and an application network blackout does not physically disable an Azure region.

## 3. Workload and measurement design

**Phase boundary:** 本节实际应用流量、交易/库存/cache-aside/outbox、业务 SLO/RTO/RPO 的契约用于后续 `phase=business`。本轮 `phase=infra` 使用 §0.3 的有限技术探针与技术数据完整性，仍需云端无故障基线、独立证据、stop/recovery 和实测故障；没有业务接口不阻塞已独立合格的 infra case。不能把技术通过写成本节业务目标通过。

### Cloud AKS test harness

- Run both the real application canary and an independent verification Job. A raw database ping or SDK probe alone cannot establish business resilience.
- Mount scripts through ConfigMaps; use validated, pinned tool images, resource requests/limits, execution deadlines, finite retries, and cleanup policies.
- Use least-privilege workload identities and secret references. Never mount a host Docker socket or grant general node privileges to business validation Jobs.
- Use application test hooks or dedicated protocol-aware proxies for simulations. Keep TLS validation enabled; do not introduce a plaintext network bypass.
- A proxy/hook must demonstrably affect the selected application path. Account for SQL/Redis/AMQP persistent connections, connection pools, and all relevant cluster endpoints.
- If in-cluster network injection is later selected, separately validate the AKS extension preview's private-cluster support and compatibility. Installing classic Chaos Mesh is not a universal prerequisite.
- Keep observability and recovery access outside the injected path. An independent recovery operator must be able to remove a fault even if the canary stops responding.
- Separate fault-target namespace, unaffected control workload, and restricted verification/evidence namespace. Freeze actual matched pods and maximum affected count; percentage rounding can affect one pod even at low percentages.
- Treat phased Jobs as approved traffic, not passive configuration. The default 900-second Job cannot contain a 15-minute baseline plus exposure plus 10-minute recovery. Use separately approved finite phases with continuous independent observations across transitions; a gap is missing evidence, not healthy recovery.
- The HTTPS probe's socket timeout is not a hard end-to-end cancellation deadline. Verify actual deadlines in the application/protocol client. The outer finite Job budget only limits harness lifetime.

### Synthetic critical flows

| Service | User flow to exercise continuously | Integrity evidence |
| --- | --- | --- |
| MySQL / PostgreSQL | Create an order with an idempotency key; update inventory in the same transaction; read the acknowledged order. | Independent ledger of attempted/acknowledged IDs; unique business effects; transaction invariants; no half-completed order/inventory updates. |
| Both Redis products | Read an item through cache-aside; update the source of truth and invalidate/refill its cache entry. | Source-of-truth comparison, version/freshness checks, cache hit/miss rate, bounded backing-store reads. |
| Storage | Upload a blob with a unique operation ID; download and verify it; exercise application retries for interrupted transfer. | Hash, length, object/version metadata, acknowledgment ledger, and absence of duplicate logical uploads. |
| Service Bus | Publish an order event, consume with PeekLock, persist its business effect, and settle the message. | Producer acknowledgments, consumer attempt ledger, one committed business effect per ID, outstanding messages, DLQ reasons. |
| Event Hubs | Publish uniquely identified events to known partitions; consume through a dedicated group, commit the business effect, then checkpoint. | Producer ack/unknown ledger, partition offsets/sequence, durable checkpoints and unique effects. No unsupported global ordering or exactly-once delivery claim. |
| Cosmos DB, if selected | Write/read a synthetic business item with an explicit partition key and concurrency/idempotency contract. | Ack/unknown ledger, version/ETag/session evidence, observed freshness and conflict reconciliation under the chosen consistency/write mode. |
| RocketMQ | Publish unique business events with the configured acknowledgment mode; commit consumer effects before successful acknowledgment. | Broker/store health, publish outcomes, redelivery/retry/DLQ records and unique durable business effects. State the actual flush/replication guarantee. |
| AKS pods/nodes | Drive the actual application flows while selected compute becomes impaired/unavailable. | Correlated target pod/node events, request outcomes, independent durable ledgers, readiness/placement/capacity and recovery timeline. |

These are proposed reference flows. Before execution, map them to actual application endpoints and business invariants. If only synthetic direct clients exist, report the result as client-library resilience, not full application validation.

For DB transactions whose commit response is lost, treat the outcome as **unknown** until reconciled by idempotency key. Do not blindly retry a non-idempotent write. For Service Bus, duplicate delivery is expected in some failure paths; duplicate business effects are not.

### Proposed acceptance targets for review

These are **project proposals, not Microsoft SLAs or universal service guarantees**.

| Dimension | Initial proposal |
| --- | --- |
| Baseline | 15 minutes; at least 1,000 relevant business operations; >=99.9% success and within the application's agreed latency SLO. Extend the window at low traffic rates. |
| Normal simulation exposure | 60 seconds initially; increase to 180 seconds only after a clean recovery. One application canary; one dependency. |
| End-to-end request deadline | 10 seconds for synchronous reference flows; replace with the actual business deadline before execution. No retry chain may exceed it. |
| Retries | Bounded exponential backoff with jitter; proposed maximum 3 retries total across all layers. Do not multiply SDK and application retries unintentionally. |
| Cache fallback | >=99% business success during cache-only loss, with p95 <=2x baseline, if the source of truth has verified fallback capacity. Otherwise require explicit, truthful bounded failure. |
| Dependency hard outage | A read/write requiring that unavailable dependency may fail. It must fail explicitly within the deadline or be durably queued under the agreed business contract; no false success. Unaffected control flow stays within baseline SLO. |
| Post-fault recovery | Return to the agreed SLO within 120 seconds after a short simulation is removed; then maintain it for 10 consecutive minutes. |
| DB HA failover | Proposed end-to-end RTO <=180 seconds from fault initiation and zero lost acknowledged committed transactions; confirm workload realism with replay backlog and connection-pool behavior. |
| Redis reconnection / warm-up | Proposed reconnection <=120 seconds after path restoration; hit ratio within 10 percentage points of baseline within 10 minutes. Recent cache writes can be lost; cache availability is not a durability guarantee. |
| Messaging recovery | Account for every acknowledged message; no duplicate committed business effect. Drain the bounded test backlog within 10 minutes after recovery, allowing the approved TTL/DLQ policy. |
| Storage planned failover | Separate maintenance window: reserve 3 hours for failover, verification, and failback. Proposed <=90 minutes per transition, to be confirmed for account size/features; no acknowledged object loss. |
| PITR / regional recovery | Agree RTO and RPO per target, backup/replication configuration, and data size before execution. No assumed zero RPO for asynchronous replication or backup restore. |

### Measurement definitions

- **Business success rate:** operations satisfying the agreed synchronous or durable-acceptance contract / attempted relevant operations. HTTP 2xx, a SQL ping, queued-in-memory work or Azure Action success alone is not business success.
- **Retry amplification:** total downstream attempts / original logical operations, with SDK/application/worker retries counted together. Freeze offered workload rate and compare downstream attempt rate separately for stop evaluation.
- **Integrity:** zero missing acknowledged durable effects, zero duplicate committed business effects, zero broken stated invariants. Unknown outcomes must be reconciled; unresolved IDs make integrity Inconclusive, never zero-loss.
- **RTO:** fault/incident initiation to sustained application SLO recovery; also record first restored service and backlog completion. **RPO:** observed acknowledged data gap at recovery, in operation counts and time; do not infer it from configuration alone.
- **Sustained recovery:** ten consecutive one-minute windows meet the selected success/latency contract, each with a pre-agreed minimum sample count; missing windows are Inconclusive. An aggregate ten-minute percentile cannot prove all windows passed.
- Baseline operations count logical business work, not retries or probe requests. At 1,000 operations, >=99.9% allows at most one failure; this is a finite acceptance check, not statistical certification of a long-term SLA. Record sample counts per path/window and do not fabricate p99 from insufficient traffic.

Measure separately: fault start, observed impact, alert, recovery decision, recovery action, dependency availability, application SLO recovery, and backlog completion. RTO for operator-driven DR includes detection and decision time, not just the Azure operation.

For simulations, also record time from fault removal to recovery. Do not use that shorter metric as a substitute for incident RTO.

## 4. Common client-path cases

Each case inherits the baseline, canary scope, measurement, and stop rules above. Re-run separately against each selected service's actual client protocol. C-01 through C-05 are hooks/proxy simulations, not service-direct Actions; skip non-applicable semantics explicitly rather than fabricating a protocol response. Pod-wide network faults affect all pod containers/destinations and are not equivalent to isolating one dependency.

| ID / priority | Hypothesis and procedure | Pass evidence / recovery |
| --- | --- | --- |
| C-01 / P0 | **Connection blackout:** interrupt established and new connections from one canary to one dependency for 60 seconds. Leave the control client unaffected. | Deadlines honored; retry volume bounded; no false success or duplicate effects; control healthy. Remove the injection, recreate only affected test connections if necessary, and prove application recovery. |
| C-02 / P0 | **Latency degradation:** introduce +100 ms, then +500 ms in separate runs for 60 seconds each; do not change shared routes. | Pool/worker queues remain bounded; timeouts and circuit-breaker behavior match the agreed contract; p95/p99 and retry amplification captured. Remove delay and verify queues and pools normalize. |
| C-03 / P0 | **Ambiguous acknowledgment:** for a bounded set of synthetic operations, permit the request to reach the service but interrupt its response or settlement. Use a protocol-aware hook where required. | Reconcile unknown outcomes; one business effect per ID; no lost acknowledged durable work. Remove the hook and reconcile every selected ID. |
| C-04 / P1 | **Dependency DNS failure:** break resolution only for the test workload's dependency hostname for 60 seconds; test both reused and newly created connections. | Correct dependency-specific alerting, bounded failure, re-resolution and reconnect after removal. Existing sockets alone cannot establish successful DNS fault coverage. Restore only test-local DNS configuration. |
| C-05 / P1 | **Throttle/resource-limit response:** use bounded client hooks matching the actual SDK's error semantics. Use HTTP 429/503 only for applicable HTTP APIs; do not fabricate HTTP responses for SQL, Redis, or AMQP. | Retry only retryable errors; honor applicable server delay; bounded concurrency; no OOM or retry storm. Disable the hook, drain work, and verify recovery. This is simulation, not proof of real Azure throttling. |

Authentication refresh failures can be added later with a dedicated test identity. Do not revoke shared permissions or change production credentials to simulate them.

## 5. Service-specific test cases

### 5.1 Azure Database for MySQL Flexible Server

Prerequisites: approved Flexible Server, healthy eligible HA standby for M-01, tested backup availability for M-03, FQDN-based connection strings, and transaction/idempotency verification. Distinguish same-zone HA from zone-redundant HA. Neither a forced HA failover nor a restart is a complete region outage. See [MySQL HA][mysql-ha] and [backup/restore][mysql-backup].

| ID / priority | User story, hypothesis, and fault | Scope / exposure | Acceptance and recovery |
| --- | --- | --- | --- |
| M-01 / P0 | As an order writer, I can continue after HA primary failover without losing committed orders. Use the MySQL failover Action under steady read/write load. | One dedicated HA server; one failover; proposed 5-minute Action duration subject to catalog validation. Select `RestoreOnStop=false` initially to avoid an unreviewed second transition. | Meet HA RTO; zero acknowledged transaction loss; pools reconnect via FQDN; inventory invariants hold. Verify the new primary and healthy HA. A planned return to the original primary is a separately authorized transition. |
| M-02 / P0 | As a user, I receive a bounded error or safe retry during a database restart, and service returns without manual application restart. Use the restart Action. | One dedicated server; one Discrete restart, not a timed 60-second outage. | Measure actual outage; no retry storm; no partial transactions or duplicate orders. Wait for Ready, rebuild stale connections, validate data and application SLO. |
| M-03 / P1 | As an operator, I can recover accidentally altered synthetic records to a chosen restore point. Use native PITR, not a Chaos failover Action. | One test fixture; record a checkpoint, alter only its data, restore to a new isolated server. | Restored pre-checkpoint records and invariants match; RTO/RPO measured; restored authentication/private networking verified. Do not overwrite or destroy the source. Cutover is optional and separately authorized. |
| M-04 / P1 | 独立 read replica 路径不可用时，主服务和恢复路径保持在约定边界。先评审专用 replica 的客户端局部隔离；无安全对应原生 Action 则标 simulation。 | 必须有实际独立 read replica、专用测试流量、lag/连接基线与准确目标；托管 HA standby 不是 read replica。当前 AwaitingTarget / PendingDesign，不把未证实目标当永久 Blocked。不得改共享 replica NSG 或扩大到主服务。 | 证明 replica 测试路径确实失效、主路径/control 不受损；移除本次隔离，恢复连接、lag/replication 与合成读写。客户端隔离不能宣称 replica 服务自身停机或 service-to-service replication 被切断。 |

The MySQL HA documentation describes typical failovers of 60-120 seconds; this is not an end-to-end application guarantee. Geo-restore requires separately verified geo-redundant backups and is outside the default wave.

### 5.2 Azure Database for PostgreSQL Flexible Server

Prerequisites: healthy eligible HA primary/standby, supported compute tier, FQDN, valid connection-pool configuration, and backup readiness. Do not silently substitute read-replica promotion for HA failover. See [PostgreSQL HA][pg-ha] and [backup/restore][pg-backup].

| ID / priority | User story, hypothesis, and fault | Scope / exposure | Acceptance and recovery |
| --- | --- | --- | --- |
| P-01 / P0 | As a transactional user, I retain acknowledged writes during a planned primary transition. Use `PlannedFailover` under load. | One dedicated HA server; one transition; proposed 5-minute duration subject to schema. Set `RestoreOnStop=false`; require eligibility rather than silently skipping. | HA RTO and integrity pass; pool reconnects; existing transactions are safely completed/retried/reconciled. Verify primary role and restored HA before another transition. |
| P-02 / P1 | As a user, I recover from an abrupt primary transition even with in-flight transactions. Use `ForcedFailover` only after P-01 recovers cleanly. | Same dedicated fixture; a new, separately authorized run. Capture WAL backlog and long-running transactions first. | Zero lost acknowledged committed writes for the healthy HA scenario; unknown commits reconciled; replay time measured. Wait for restored HA and application SLO; authorize failback separately. |
| P-03 / P1 | As an operator, I can restore corrupted synthetic data. Use native PITR to a new isolated server. | Chosen restore time within retained/available backups; no source replacement. | Validate restored records, schema, application compatibility, private networking, identities, RTO, and restore-point gap. Remove only approved temporary fixtures after evidence retention. |

WAL replay and workload can extend failover beyond typical timings. Same-zone HA cannot establish zone-loss resilience; the proposed HA RPO does not apply to asynchronous cross-region replica promotion.

### 5.3 Azure Cache for Redis

Assumption: "Azure Cache" means **Azure Cache for Redis**, not Azure CDN or another cache product. Confirm the product and SKU. Reboot coverage below applies to Basic/Standard/Premium `Microsoft.Cache/redis`; replica-specific tests require a replica. Enterprise is not this reboot path. See [cache administration][cache-admin].

| ID / priority | User story, hypothesis, and fault | Scope / exposure | Acceptance and recovery |
| --- | --- | --- | --- |
| R-01 / P0 | As a cache-aside reader, I remain served during primary reboot using reconnect/fallback. Use `RebootType=PrimaryNode`. | One dedicated eligible cache; one reboot. For clustering, one explicit shard first; deliberately route selected keys there. | Cache fallback contract, bounded source load, topology refresh, and integrity pass. Verify cache availability and warm-up; no promise of cache-write durability. |
| R-02 / P1 | As a reader, I am not substantially disrupted by replica reboot. Use `SecondaryNode`. | Dedicated Standard/Premium target with a replica; one reboot; no simultaneous primary fault. | Control/application stay within agreed SLO; replica rejoins; redundancy restored. Basic is Blocked for this case, not a successful skip. |
| R-03 / P1 | As a user, I survive cold-cache misses without overwhelming the database. Expire/invalidate only approved synthetic keys through a test hook. | Bounded hot-key set; one workload; no whole-cache flush by default. | Bounded refill concurrency, correct values, warm-up target, and healthy source of truth. Disable the hook and rebuild only test keys. |
| R-04 / P1, destructive | Legacy Redis 全数据库 flush 后，明确可重建的测试数据恢复。没有已确认的 legacy Workspace flush Action；单独评审受控 data-plane native drill，不伪造 control-plane Action/log。 | 专用且完全独占、可重建数据库；确认产品/cluster/数据库支持及所有消费者，准确 flush 范围。TLS/Entra 身份不降级，禁止启用 access keys；认证/恢复待核验为 PendingVerification，删除许可为 AwaitingAuthorization，未完成不运行。不得触及 sessions 或唯一持久数据。 | flush 实际生效、非目标不受损；明确预期删除的测试 keys，按已记录数据重建并验证读写/版本。仅删少量 keys 属 R-03，不算此 case；flush 无 undo，恢复失败必须报 Failed。 |

Exclude `AllNodes` from the initial wave. Reboot is not a cache flush and can still lose recent data. Existing Azure Cache for Redis deployments can be tested, but Microsoft recommends migration to Managed Redis; migration itself is not part of this plan.

### 5.4 Azure Managed Redis

Verify actual product/SKU even though the resource type is `redisEnterprise`. Determine whether data is disposable cache data or non-reconstructible sessions/state. Do not promise zero data loss from asynchronous Redis replication. See [Managed Redis architecture guidance][amr-waf] and [active geo-replication][amr-geo].

| ID / priority | User story, hypothesis, and fault | Scope / exposure | Acceptance and recovery |
| --- | --- | --- | --- |
| A-01 / P0 | As a cache-aside user, I remain served when the Managed Redis client path disconnects. Apply C-01 with a cluster-aware client. | Selected canary and dedicated database path for 60 seconds; no service-node reboot claim. | Fallback, deadlines, topology refresh, warm-up, and source integrity pass. Remove the injection and prove real requests succeed. |
| A-02 / P1, destructive | As a user, I survive complete loss of reconstructible cache data. Use the flush database Action. | Dedicated disposable instance/database only; one flush. If geo-linked, ALL linked caches must be disposable and authorized. Unverified ownership is PendingVerification; pending deletion approval is AwaitingAuthorization. Confirmed non-reconstructible data is a safety Blocked condition; do not flush. | Approved cache fallback and source load limits pass; rebuild from source and verify warm-up. Cancellation cannot restore erased data. Never run against the only copy of durable business/session data. |
| A-03 / P1, regional | As a regional user, I redirect to a healthy geo-linked instance when my local cache path is unavailable. Isolate only the regional test clients, then execute the application's endpoint/identity redirection. | Dedicated eligible active geo-replication group; supported HA/SKUs/version/modules, matching configurations, and alternate private access verified. | Detection-to-recovery RTO, application-measured freshness/RPO, concurrent-write invariants, and healthy alternate region. Restore the path; verify convergence before traffic returns. This is regional client isolation, not an Azure region failure. |
| A-04 / P2, topology-changing | As an operator, I can remove an unavailable geo member without destabilizing healthy members. Use force-unlink with explicit linked database IDs. | Dedicated disposable group only; separate authorization for unlink and recovery lifecycle changes. | Healthy members remain usable; memory/replication behavior recorded. Follow the documented recovery procedure, including deletion/recreation of the affected test member where required; verify rejoin/convergence before returning traffic. |

Force-unlink is a recovery/topology action, not a substitute for inducing a real outage. Client isolation does not interrupt service-to-service replication; do not claim it proves metadata accumulation during a true regional loss.

The Geo Replication Healthy metric is a health indicator, not a numeric lag measurement. Measure freshness using application version markers. Managed Redis export/import recovery is not included by default: current guidance notes limitations with firewalled/private-link storage, and this plan must not weaken the network boundary to enable it.

### 5.5 Azure Storage account

Initial business scope is **Blob Storage**. Add explicit workload variants for Azure Files, ADLS Gen2, Queue, or Table if used; Blob results do not cover those protocols/semantics.

See [DR guidance][storage-dr], [planned failover behavior][storage-planned], and [initiation prerequisites][storage-start].

| ID / priority | User story, hypothesis, and fault | Scope / exposure | Acceptance and recovery |
| --- | --- | --- | --- |
| S-01 / P0 | As an uploader, I either complete a verified upload or receive a truthful bounded failure during connection reset/transient errors. Apply C-01/C-03/C-05 to the Blob application path. | Dedicated container/prefix and selected canary; bounded operations and 60-second exposure. | Hash/length and acknowledgment ledger reconcile; no duplicate logical object or false completion. Remove injection, reconcile interrupted uploads, and validate reads/writes. |
| S-02 / P1 | As a read-only user, I can use the secondary endpoint when the primary client path is unavailable. Use application-controlled read fallback. | Dedicated RA-GRS/RA-GZRS account; selected reads only; confirm secondary service support and private access. | Reads respect agreed freshness; secondary is not used for writes; a not-yet-replicated object is handled correctly rather than declared lost. Restore primary path and verify application return. |
| S-03 / P1, account-wide DR | As an operator, I can move a geo-redundant account and restore service with no acknowledged object loss. Use the planned failover Action. | Dedicated account only, including every service/entity in it; synchronization complete; both regions healthy. Reserve the separate 3-hour window. | Measure end-to-end RTO; reconcile acknowledged objects and private DNS/access. After healthy verification, separately authorize planned failback and confirm original redundancy and replication. Stop cannot undo this Discrete transition. |
| S-04 / P1, recovery | As a user/operator, I can recover a deleted or overwritten synthetic blob using configured protection. Use version/soft-delete recovery, not regional failover. | Dedicated protected fixture; verify actual enabled protection and retention first. | Restore intended content/version and hash within agreed RTO; do not overwrite newer valid business data. Clean up only explicitly selected test objects. |

Do not fail over a Terraform backend account, backup repository, shared account, or account carrying recovery/observability dependencies. LRS/ZRS alone cannot support regional account failover.

Review the account's feature support matrix before S-03, including HNS, change feed/object replication, policies, and every storage service present. For Azure Files, stop all application/client share activity before failover and validate remount/reconnect afterward.

Planned failover requires both regions available, can take about an hour, and is **not** a test of recovery when the primary storage region is truly unavailable. Geo-redundancy is retained, but effective redundancy can change during the transition (for example GZRS to GRS) and return on planned failback. Verify actual state; do not let Terraform revert it mid-drill.

Unplanned account failover is excluded from default execution: it can lose unreplicated writes, remove geo-redundancy, and introduce inconsistencies. Add it only as a separately approved disposable-environment drill with an explicit data-loss budget and re-protection procedure.

### 5.6 Azure Service Bus

Use explicit dedicated queue/topic/subscription names and finite backlog/message TTL. Durable business events use PeekLock, not ReceiveAndDelete. See [message settlement/locks][sb-locks], [Geo-Replication][sb-georep], and [Geo-DR][sb-geodr].

| ID / priority | User story, hypothesis, and fault | Scope / exposure | Acceptance and recovery |
| --- | --- | --- | --- |
| B-01 / P0 | As a producer, I do not lose accepted business work when sends are disabled. Use queue state `SendDisabled`. | One dedicated queue, explicit `queues`; proposed 60-second duration subject to schema. | Sends fail truthfully or enter an approved durable outbox; existing messages remain consumable. Verify actual state recovery, explicitly restore the recorded state if needed, replay outbox, and reconcile IDs. |
| B-02 / P0 | As a consumer/operator, I recover from paused receives without backlog loss. Use `ReceiveDisabled`. | One dedicated queue for 60 seconds, with bounded publishers. | Backlog grows within its cap; alerts fire; send behavior verified; recovery drains without duplicate business effects. Restore recorded queue state and prove send/receive/settlement. |
| B-03 / P1 | As a subscriber, I recover after a topic or subscription is disabled. Execute separate runs of the topic and subscription state Actions. | Explicit topic/subscription list only; Discrete disable; planned 60-second hold managed by the operator, then explicit restoration. | Verify actual accepted/rejected work and affected subscriptions; no assumption that a disabled subscription accumulates backlog. Restore the original state even if the run is canceled; reconcile deliveries and DLQ. |
| B-04 / P0 | As an event processor, I avoid duplicate effects after connection/lock/settlement loss. Interrupt the selected consumer after business commit but before completion; also test handler delay beyond lock-renewal budget. | Bounded message cohort; canary consumer only; no global lock-setting change. | Redelivery handled idempotently; duplicate attempts allowed but only one effect; DLQ reasons reconcile. Remove fault, drain or explicitly dead-letter test messages, and verify lock renewal. |
| B-05 / P2, regional | As an operator, I recover messaging across regions with a known data contract. Prefer a native planned Geo-Replication promotion. | Dedicated eligible Premium namespace with synchronized secondary; current region support, identities, and private access verified. Not a queue-state Chaos Action. | Stable namespace hostname reconnects; planned promotion preserves acknowledged message data/state; end-to-end RTO and message ledger pass. Re-synchronize and authorize reverse promotion separately. |

Geo-Replication replicates metadata **and messages/state**. Synchronous and asynchronous modes have different latency, availability, and RPO behavior; forced promotion in asynchronous mode can lose data or duplicate effects and is excluded by default.

Geo-DR is a different, mutually exclusive configuration: it replicates **metadata only**, not queue/subscription/DLQ messages, and alias failover breaks the pairing. If the existing environment uses Geo-DR, define a separate outbox/replay and re-pairing drill rather than treating B-05 as applicable. Verify secondary RBAC and network configuration independently.

### 5.7 Event Hubs

Use dedicated entities, a dedicated consumer group and separately protected checkpoint storage. Freeze partitions, retention, producer acknowledgment semantics and replay capacity. Event Hubs is a retained partitioned stream, not a Service Bus queue; there is no message settlement/PeekLock contract or general per-message DLQ supplied by this case.

| ID / priority | Hypothesis and mechanism | Scope / exposure | Acceptance and recovery |
| --- | --- | --- | --- |
| H-01 / P0 | An application retains/rejects work truthfully while event publishing is disabled. Use the event hub state Action with `SendDisabled`. | One dedicated event hub, explicit `eventhubs`; proposed 60 seconds subject to schema; bounded publishers. | Durable outbox or truthful deadline failure; existing consumer behavior observed; ack/unknown IDs reconciled. Verify original state restoration, replay and backlog drain. |
| H-02 / P1 | A full entity disable does not lose accepted work or create duplicate effects after recovery. Use `Disabled`. | Separate run on the same isolated hub; record prior state, dedicated consumer group/checkpoint and retention margin. | Verify actual send/receive impact; no assumption that a disabled entity retains all new attempts. Restore original state, resume from durable checkpoints and account for all acknowledged events before retention expires. |
| H-03 / P0 | Consumer termination after effect commit but before checkpoint is safe to replay. Use an application hook or qualified pod delete, not an entity-state Action. | Bounded event cohort; canary consumer group only; no checkpoint backend fault. | Duplicate delivery allowed, one effect per ID; per-partition ordering contract honored. Resume/rebalance consumers, reconcile offsets and drain within the agreed deadline. |
| H-04 / P1 | 暂停专用 consumer group/隔离其测试消费路径，有限 producer 继续发布，验证积压、告警与恢复追赶。属于 client/consumer simulation，不是 namespace outage。 | 专用 hub/group、有限 input rate/总量、partition lag/bytes/retention 数值上限；durable checkpoint 与 observer 在故障外。不得撤共享 SAS Listen、全局 RBAC 或所有消费者权限。 | 实测各 partition offset/sequence 与 checkpoint lag 增长、producer ack/unknown；恢复原测试消费路径，从正确 checkpoint 追赶，保留/重放每个已确认测试事件，无错误 checkpoint 越过未提交 effect。retention 或恢复期限待确认时为 PendingVerification，不执行。 |
| H-05 / P2, regional | Service-native metadata Geo-DR alias failover；验证新 endpoint/configuration 可用，不声称事件数据复制。 | 专用合格 primary/secondary、alias、实际 pairing、secondary RBAC/私网、旧事件/checkpoint 的保留与恢复计划。当前 secondary/配置未核验为 PendingVerification；此操作可能打破 pairing，恢复生命周期需独立授权。 | 正确 alias 指向 secondary，技术 publish/read 恢复；明示旧 events/checkpoints 不随 metadata failover 复制，单独记录旧侧可读/重放/缺失情况。恢复/重新 pairing 按已批准 runbook，不能将一次切换称可自动 failback 或零丢失。 |
| H-06 / P2, regional | Service-native data Geo-Replication 的获支持 promotion，按实际 sync/async 契约验证数据/状态恢复；与 H-05 分开。 | 当前 region/SKU/API 支持、专用 primary/secondary、复制健康/同步、private access/RBAC、独立 checkpoint 与批准的 RPO/recovery contract；不因 Standard namespace 或 zone HA 默认可用。未经审查不强制提升可能丢数据的 async secondary。 | 原生 promotion 与新侧数据访问真实生效，逐 partition/ID 对照 ack/unknown、复制与 checkpoint 状态；检查唯一技术 effects，不承诺全局顺序/exactly-once。重新同步、身份/网络和回切另审，未知数据差距为 Inconclusive。 |

Backlog is assessed per partition and in time behind the stream, not only message count. Require available retention to exceed the approved disruption plus worst-case replay and evidence margin. Geo-recovery is outside these cases; do not label entity state changes a regional outage.

### 5.8 Optional Cosmos DB

These cases apply to a verified Cosmos DB for NoSQL application contract. Other APIs require their own SDK/error/consistency variants. A module or account with one region is not an eligible offline-region campaign. Agree partition keys, consistency, session handling, write-region/automatic-failover configuration and conflict policy before selecting a case. See [Cosmos DB reliability][cosmos-reliability].

| ID / priority | Hypothesis and mechanism | Scope / exposure | Acceptance and recovery |
| --- | --- | --- | --- |
| D-01 / P1 | The client tolerates bounded throttling/transport failure without retry storms or duplicate writes. Apply C-01/C-03/C-05 with NoSQL SDK semantics. | Dedicated items/partition keys and selected canary; 60 seconds; no shared throughput reduction. | Honor applicable retry-after/deadline; reconcile ack/unknown writes, ETags and expected consistency. Remove hooks and prove reads/writes; simulation is not actual regional/RU exhaustion. |
| D-02 / P2, regional | An eligible multi-region account/application routes around an offline region. Use `microsoft-documentdb-offlineregion/1.0` with explicit `RegionName`. | Dedicated approved account and all affected regions/clients, not container-only scope. Validate role, read/write mode and actual regional impact first. | Meet agreed RTO/RPO/consistency and conflict contract, healthy alternate access, no missing acknowledged durable work outside the approved data-loss contract. Confirm region reintegration, replication and traffic return; cancellation alone is not restoration proof. |

No zero-RPO promise is made for every consistency/failover configuration. D-02 is Unselected in this campaign; if selected later, regional Action schema and account topology are PendingVerification, not assumed incompatible. Do not add a second region merely to complete coverage.

### 5.9 AKS pods

Use the operator-owned [AKS extension][aks-extension], not classic Chaos Mesh. All five extension IDs below use **1.0.0**, unlike the service-direct `name/1.0` IDs. Structural Action duration is at least `PT1M`; effect parameters remain within the module bounds. Qualify private-cluster behavior without opening public access. Review narrowly scoped helper admission/security only where required, never relax verification or cluster-wide policy.

| ID / priority | Hypothesis / extension Action | Initial containment | Acceptance and recovery |
| --- | --- | --- | --- |
| K-01 / P0 | Workload replacement preserves business outcomes: `urn:csci:microsoft:containerservice:poddelete/1.0.0`. | Exact namespace AND labels; graceful deletion; preview percentage rounding and replacement membership; interval longer than exposure. One dedicated recoverable canary cohort. | Prove intended pods were deleted and replacements served real traffic; requests/ledgers meet contract. Pod delete is not cancelable; stop further injection, verify controllers/readiness and data. |
| K-02 / P1 | CPU contention yields bounded latency and contains resource pressure: `urn:csci:microsoft:containerservice:podcpuhog/1.0.0`. | Verified target container tools and Linux amd64 placement; begin with 1 core only if capacity budget permits; <=60 seconds. | Business SLO/degradation contract, neighbor/control health and bounded queues; observe HPA behavior rather than assume scale-out. Remove effect and verify actual CPU, readiness and SLO recovery. |
| K-03 / P1 | Memory pressure is contained and restart paths preserve durable work: `urn:csci:microsoft:containerservice:podmemoryhog/1.0.0`. | Explicit container and measured memory headroom; select within 1-128 megabytes and approved pod percentage. OOM/restart risk acknowledged. | No unintended node/neighbor pressure or data corruption; observe OOM/restarts and reconciled effects. Remove pressure; restore healthy replicas and sustained business SLO. |
| K-04 / P1 | Pod-wide delay preserves bounded timeouts/retries: `urn:csci:microsoft:containerservice:podnetworklatency/1.0.0`. | Network daemon/support confirmed, Linux amd64 pods, begin +100 ms within 1-500 ms, <=60 seconds. Include sidecar impact in authorization. | Actual delay visible on relevant traffic, bounded pools/retries and healthy control. Verify all affected connectivity after removal and inspect helper/container restarts. |
| K-05 / P1 | Partial packet loss does not create retry amplification or false acknowledgments: `urn:csci:microsoft:containerservice:podnetworkloss/1.0.0`. | Same network gate; begin 1% within 1-10%, <=60 seconds; no inherited 100% default. | Prove loss on relevant traffic with enough volume; reconcile unknown writes, latency and attempts. Verify removal; an early-deleted helper makes intended exposure unproven. |
| K-06 / P1 | 单 Pod 内存逐步增长模型，观察 limits、OOM/restart 与恢复；是专用 bounded simulation，不把固定 memory hog K-03 称为真实泄漏。 | 仅 operation-owned 测试进程/容器、精确 namespace/labels、明确增长速率/bytes/终点/超时、保留 node headroom；先低强度。当前原生机制未映射为 PendingDesign，权限未批为 AwaitingAuthorization；不为本轮编写模拟，不修改全局 OOM/安全策略。 | 实测逐时增长曲线而非仅高内存；记录是否触发约定 OOM/restart、非目标/node health、持久技术数据与恢复。终止本次精确进程/模拟，内存回落或已批准替换测试 Pod，持续 Ready/读写，不能残留增长进程。 |

Published caveats: private clusters are **unvalidated**, not universally unsupported; CPU/memory on some Cilium/service-mesh configurations are also unvalidated. Pod delete helper pods fail in PSA-restricted target namespaces. Network faults can persist after container restart even when the run says `Succeeded`; recovery may require separately authorized replacement of affected test pods. A PDB does not guarantee injected deletion/node loss obeys voluntary-eviction protection.

### 5.10 AKS nodes and private RocketMQ VM

Node-level tests do not require the pod extension. Discover AKS `nodeResourceGroup`, approved user-pool VMSS and actual instances/zones through the cluster, not a hardcoded `MC_*` name. Do not import/manage AKS VMSS lifecycle. NAP pools are excluded. See [AKS node guidance][aks-nodes].

| ID / priority | Hypothesis and mechanism | Scope / exposure | Acceptance and recovery |
| --- | --- | --- | --- |
| N-01 / P1 | Loss of the approved user-pool zone preserves the application's agreed outcome. Use allowlisted VMSS shutdown. | Exact VMSS IDs plus one verified location/zone; inspect **all** matching instances, remaining capacity, replica placement, storage zone constraints and autoscaler. Separate window; no system/recovery pool. | Nodes actually unavailable; intended blast radius only; pods reschedule or fail within agreed contract; durable ledgers and application recovery pass. Confirm node readiness, capacity and storage after stop; do not promise automatic redistribution or full-zone-outage equivalence. |
| V-01 / P1 | RocketMQ survives a broker VM restart according to its actual durability contract. Use `microsoft-compute-restart/1.0`. | One dedicated private broker VM, selected test topics/groups; NameServer dependency and standalone/HA architecture documented; never jumpserver. | Verify broker/store and client reconnect, ack/unknown message reconciliation and unique effects. Restart has no undo; verify systemd/bootstrap completion, NameServer registration and sustained send/consume, not just VM Running. |
| V-02 / P2, deferred | Bounded broker resource pressure does not harm other workloads or lose durable accepted work. Native CPU/memory Actions provide the mechanism; broker business acceptance is a separate contract. | Dedicated VM, verified OS/managed identity/public outbound, reviewed intensity and storage/memory limits. Single-VM mechanisms are module-allowlisted under V-03/V-04; the native run installs and retains its agent extension. | Agent effect and real load proven; bounded retry/backlog and durable message contract; remove effect and verify broker/store/business recovery. Unselected business case, not a mandatory Blocked item; V-03/V-04 prerequisites remain separate. |

A standalone broker restart may legitimately stop service; accept only truthful bounded failures or approved durable queuing, never invent HA. Disk persistence and sync/async flush/replication determine whether a broker acknowledgment is durable. Freeze that contract before V-01.

### 5.11 VM infrastructure cases

V-03–V-10 与 V-01/V-02 的 broker 业务目标不同。可规划复用当前 RocketMQ VM，但运行前核对所有现有进程/数据/消费者、允许中断及独立恢复；不能因为不测 broker 业务就忽略 VM 故障对 broker 的影响。OS、broker 持久数据、backend/evidence/恢复盘不作为 disk fault 目标；jumpserver 不作为任何 fault 目标。

| ID / priority | 目的、机制与步骤差异 | 前置、范围与参数 | 验收与停止恢复 |
| --- | --- | --- | --- |
| V-03 / P1 | Workspace `microsoft-compute-cpuPressure/1.0`，Continuous CPU pressure。完成 agent 资格后逐级施压，不直接照搬所有 cores 100% 长时占满。 | 已实现默认关闭的单 VM 配置；实际 OS/agent、身份/网络、CPU baseline、恢复 headroom 及 `pressureLevel`/duration 仍需云端核验。目标必须进入已核验 agent allowlist；初始 ≤50%，更高配置需单独 opt-in，运行另授权。 | 实测目标 CPU/相关进程负载达到批准范围，非目标与独立观察可用；取消/结束后 agent effect 消失、CPU 回基线、guest health/技术读写恢复。未达效果或监控缺失不能 Passed。 |
| V-04 / P1 | Workspace `microsoft-compute-physicalMemoryPressure/1.0`，Continuous 物理内存压力。不是通用应用泄漏/自动 OOM 测试。 | 已实现默认关闭的单 VM 配置；agent/catalog/现有工作负载与 headroom 合格，明确 `pressureLevel` 1–99 和超时，保留 guest/recovery 操作能力。初始 ≤50%；90% 及关键进程 OOM 风险另审，运行另授权。 | 实测 memory 使用与 OOM/进程事件；未授权关键进程受损即停。移除 effect 后 memory、guest 与技术读写正常，无残留压力；不能以 Action 成功替代真实内存效果。 |
| V-05 / P1 | VM 特定测试目的地址的网络 latency/jitter；没有已确认对应 Workspace VM Action 时，先评审隔离 guest simulation。 | 单 VM、单目的地址/port/protocol/方向、实际 interface，保存原 qdisc/routes 与明确本次 handle；初始 +100 ms/60 秒。当前为原生机制未映射；权限/恢复未核验按 PendingVerification/AwaitingAuthorization 标注，不默认安装 guest 模拟或覆盖原规则。 | 实际协议 latency 达到批准变化，非目标路径健康；移除仅本次规则并比对原网络配置/连通性。ping 可辅助，不能替代应用协议影响；不得清空已有 qdisc/共享规则。 |
| V-06 / P1 | VM 特定测试路径 packet loss；与 V-05 分开单故障 simulation，不能称 Azure network outage。 | 单目的地址/port/方向、足够样本、明确实际 interface/owned rules 与独立恢复；初始 1%/60 秒。禁止改共享 NSG/DNS 或覆盖管理链路。 | 丢包和协议重试/超时实证，control 不受损；移除 owned rule 后实际协议恢复、无残留。控制/观察断开即独立 operator 停止恢复。 |
| V-07 / P1, destructive | 有限 owned 文件占用专用可销毁测试卷，模拟 bytes/inodes 耗尽；不填 OS 或 broker 数据 filesystem。 | 明确 disk/filesystem/mount 与唯一文件路径、bytes/inodes 上限/保留量、工具能力和 hard deadline；保护原数据，snapshot/恢复资格确认。不保证 fallocate 在所有 filesystem 上真实耗尽，未达效果为 Inconclusive。 | 目标卷实际使用量与预期限定写入失败；其他卷/进程/恢复健康。只删除本次确切文件，空间/inodes 回到允许基线、校验已有合成数据和读写；文件 cleanup 不等于损坏数据自动恢复。 |
| V-08 / P1 | 专用测试卷 bounded IO pressure simulation，限制 workers/IOPS/bytes/rate，单独运行，不混 V-07。 | 确认盘型、配额/节流、latency/queue baseline、测试目录/文件、精确进程 ownership、成本与 hard deadline；不触碰 broker/OS/evidence 卷。 | 实测 IO/queue/latency 或节流符合注入目标；停止本次精确进程/清理 owned files 后 IO/latency 回基线，guest/技术数据健康。其他资源受损或预算超限即停。 |
| V-09 / P1 | `microsoft-compute-restart/1.0`，单 VM 单次 Discrete restart；仅基础设施验收，不替代 V-01 broker durability。 | 正确 VM ID、允许中断的所有间接消费者、boot/guest/服务恢复 runbook、独立 observer/operator、当前健康与备份；无自动重复 restart。 | Azure operation + boot/guest/实际技术连接证明重启与恢复。stop 只能阻止进一步操作，不能 undo 重启；恢复超约定预算或已有数据/关键服务受损记 Failed。 |
| V-10 / P1 | 单 operation-owned 测试进程 termination + supervised recovery；无 guest Workspace Action 时独立 service-native drill，不套 App Service kill-process。 | 精确 PID、executable/start identity、owner 和明确 supervisor/start contract；操作前重新核对 PID 以防 reuse。禁止按名字批量 kill、杀 broker/agent/system 进程或关闭整个 VM。进程尚未选定为 AwaitingTarget，原生机制未映射为 PendingDesign，不启动。 | 原进程实际终止，按已批准机制恢复新进程/技术行为，其他进程不受损。恢复失败启动限定 runbook，不 broad catch/自动重复 kill；退出后清理 owned 测试进程，不改变原业务服务生命周期。 |

### 5.12 AKS node infrastructure cases

仅授权测试 User pool 的实际实例；当前 User pool 两节点，单节点故障可损失一半容量。声明 three zones 不证明每 zone 有实例，VMSS zone filter 不保证单实例。控制/ledger/recovery 放在实际故障之外。agent 对 VMSS 的作用范围、NAP、autoscaler/AKS reconciliation、存储/调度必须核实；不把 Pod-only 故障替代 node-wide 证明。

| ID / priority | 目的、机制与步骤差异 | 前置、范围与参数 | 验收与停止恢复 |
| --- | --- | --- | --- |
| N-02 / P1 | 测试 node CPU pressure；优先核对 Workspace VMSS CPU agent Action 是否满足实际授权实例边界。单实例作用范围未证实为 PendingDesign/PendingVerification，不压整池或另造模拟。 | node/VMSS/instance 对应、实际 vCPU/agent/pressure scope、非目标/system pods 放置与剩余容量；不为兼容模板自动压满整池。高强度单独审查。 | 真正目标主机 CPU 受压而非只一个 Pod；邻居/System pool/observer 不受损。移除效果、核实节点/Pod readiness、CPU 与容量恢复，记录 autoscaler/reconciliation。 |
| N-03 / P1 | 测试 node physical memory pressure；agent 实例作用范围同 N-02，不能用 K-03 的容器高内存冒充节点饱和。 | 实际 memory/headroom、pressure/bytes/超时、eviction/OOM 风险、System/恢复组件排除；实例/恢复边界待核验为 PendingDesign/PendingVerification，未完成不运行。 | 主机 memory/OOM/eviction 及目标影响实证；未批准关键组件受损即停。恢复 node/容量/技术数据与已约定的 Pod rescheduling，不假定自动迁回原节点。 |
| N-04 / P1 | 单 test node 特定路径 packet loss；当前 Pod extension 不是 node network Action，精确原生机制未映射为 PendingDesign，不补 node-level 模拟。 | 正确 interface、node/instance/目的路径、owned rules、所有受影响 Pod/sidecar 清单和独立 guest recovery。禁止全 namespaces 选择、管理/共享网络改动。 | node-level 协议丢包/重试、真实影响范围与未授权控制隔离；恢复原配置、Ready 与实际连通性。不能用 K-05 的 Pod-only 证据关此 case。 |
| N-05 / P1 | 单 test node latency/jitter，机制资格同 N-04；与 packet loss 分开。 | 明确目的路径和本次规则；初始低延迟/短时，不能照搬 all pods/长时默认。停止通道独立，预先记录原配置。 | 主机路径 latency 实证、非目标不受损；移除本次 effect 后协议/Ready/规则恢复。精确原生机制或 node 作用/恢复证据缺失为 PendingDesign/PendingVerification，不冒充通过。 |
| N-06 / P2, high-risk | 单 test node 到 API Server 路径 partition；当前未确认等价原生 Workspace Action，PendingDesign，独立可行性/恢复审查，不运行。 | 精确实例、API 目的路径、lease/eviction 实际配置、所有间接影响、guest/ARM 独立恢复及 hard deadline。禁止 shared route 改动，不照搬指向 `/dev/null`，不假定四分钟一定在 eviction 前。 | node lease/Ready/事件和实际 partition 相关，控制/其他节点未受损；恢复后 lease、Ready、调度/技术读写与网络一致。不能只看到 NotReady 就 Passed，恢复窗口超限/失控即 Failed。 |
| N-07 / P1 | 仅一个授权 test node unavailable；获支持 VMSS shutdown Action 的 zone 选择若匹配多个实例，则不执行，另审机制，不采用随机 deleteinstances。 | 当前 node/VMSS/zone 映射、实际匹配恰一个、排除 System pool、剩余容量/副本/存储约束；每次 start 前重验，不能只凭配置 zone 名字。 | 正确实例/node 确不可用、实际影响不扩大；停止/恢复后节点、容量、技术读写与数据正常。不能将单节点结果写为 N-01 entire-zone resilience；autoscaler 引入新容量须记录。 |

### 5.13 ASM control/data partition

| ID / priority | 目的、机制与步骤差异 | 前置、范围与参数 | 验收与停止恢复 |
| --- | --- | --- | --- |
| I-01 / P2 | 指定 test proxies 与 ASM/Istio control plane 断连，观察已有数据面与恢复。不是 AKS API/node partition N-06。 | 实际 ASM/Istio、proxy/control revision 与连接基线、准确 namespace/proxy 选择、独立恢复。当前 AwaitingTarget / PendingDesign；不为补齐用例安装 mesh、Chaos Mesh 或重装 extension。无对应 Action 时单独审隔离 simulation。 | 实测指定 proxy/control 连接丢失与未授权对象健康；恢复连接/同步、技术流量和原网络状态。Pod-wide loss 影响 sidecar/所有目的路径不等于仅控制面断连，不冒充等价通过。 |

### 5.14 Future Load Balancer cases

本轮无用户管理的 LB 目标；三个 case 均 Future、不执行，不把 AKS 托管 LB 纳入。后续有目标才核对 SKU、backend/probe/routing、独立控制、最小权限、配置 ownership 与恢复。

| ID / priority | 目的、拟用机制 | 范围/前置与参数 | 验收与恢复 |
| --- | --- | --- | --- |
| L-01 / P1 | 单 backend unavailable。后续核对 `microsoft-network-updateloadbalanceradminstate/1.0`、backend admin state 与区域 schema 是否匹配；否则独立 native/simulation review。 | 实际 LB、精确 backend pool/address、scope/count、健康 control 与原 admin state；单 backend，不全池。 | 指定 backend 不接流量、非目标路由符合技术契约；恢复原 admin state，probe/backend/流量恢复。admin Down 不证明后端 VM 已崩溃。 |
| L-02 / P1 | 单 backend 测试网络路径中断；与 admin-state 不互称等价。 | 本轮 Future；后续选定独立测试 backend/目的路径/owned fault rule、真实路由与 recovery；不改共享 NSG/DNS。隔离机制待映射为 PendingDesign，不阻塞本轮已有目标。 | 网络实际受损、probe/routing/连接变化及 control 证据；移除本次 effect，原网络/probe/连接正常。 |
| L-03 / P1 | 单 backend 健康探针异常；通过专用 test responder/hook/native route 单独评审。 | 准确 probe protocol/port/path/threshold 与 backend、独立 control/恢复；不默认修改共享 probe。 | 真实 probe 状态改变与流量摘除/恢复，保留判定/恢复时间；ping 不是 LB probe 证据。 |

### 5.15 Future Application Gateway cases

本轮没有 Application Gateway；G-01–G-03 均 Future。AGFC 和 Azure Load Balancer 不是等价资源；不为 case count 建 Gateway，也不猜不存在的 Workspace Action。

| ID / priority | 目的、拟用机制 | 范围/前置与参数 | 验收与恢复 |
| --- | --- | --- | --- |
| G-01 / P1 | 单 backend failure；后续评审专用 backend native/simulation，明确是否真实进程/实例故障。 | 实际 Gateway/SKU、pool/backend、监听/routing 与独立 control、授权恢复；无原生支持则显式标机制。 | 实际 backend health 与路由/技术响应受损并隔离；恢复原 backend、health/routing/连接，不等同 Gateway 整体故障。 |
| G-02 / P1 | 单 backend 测试路径 network interruption。 | 精确 backend/destination/rules 和独立恢复；不改共享 NSG、DNS、TLS 或禁用验证。 | 实测 backend 网络、Gateway health、routing 与 control；只移除本次 effect，原网络/health/技术连接恢复。 |
| G-03 / P1 | 单 backend probe abnormal；专用 test responder/hook/native 机制后续核对。 | 实际 probe protocol/hostname/path/threshold、目标 backend 和原配置；不直接扰动共享生产 probe。 | probe failure、backend 摘除与恢复、实际流量时间线；以 Gateway probe 证据判定，非 ping 或配置保存成功。 |

## 6. End-to-end extension after individual services pass

E-01–E-03 are later `phase=business` cases, not prerequisites for the current infra-first campaign. Their original acceptance remains intact; no infra result closes these application-flow cases.

| ID / priority | Hypothesis | Controlled sequence and acceptance |
| --- | --- | --- |
| E-01 / P1 | Losing the cache does not overload the database or break the order flow. | Reuse the approved cache-only disruption while real cache-aside traffic runs. Do not also fault the DB. Assert backing-store headroom, business SLO, bounded refill, and correct records. |
| E-02 / P1 | A DB commit and outgoing business event remain reconcilable during messaging loss. | Reuse B-01 during the actual order-to-outbox-to-Service-Bus flow. Verify committed DB order, retained outbox event, one eventual consumer effect, and backlog drain. No atomicity claim across services without a proven application pattern. |
| E-03 / P1 | Pod/consumer replacement does not duplicate downstream effects. | Reuse K-01 with B-04/H-03's bounded cohort and the actual application path; one pod fault only. Reconcile pre-restart acknowledged work, retries/redelivery and one durable effect per ID. |

No multi-service overlapping fault is proposed initially. A later combined outage needs a new hypothesis, cumulative impact budget, and explicit authorization.

## 7. Safety, permissions, stopping, and restoration

### 7.1 标准执行步骤（所有用例/变体共用）

本节保留完整 infra/business 验收流程。当前原生先行执行使用 §0.5 的最短流程；不要求先建设此处的自定义技术流量、账本和 observer，但目标、权限、停止与实际恢复边界仍须核对。

| 步骤 | 操作与必要记录 |
| --- | --- |
| 1. 资格/授权 | 确定 ID/variant/phase、真实目标/间接消费者/排除、假设、数值预算、操作员/恢复权限；核对当前 catalog/schema/region/SKU/HA/agent/extension、无冲突维护/运行。缺少支持/资格/授权，不开始。 |
| 2. 配置审查 | Terraform 做声明式配置；按 owning stage 使用固定工具/readonly lock、fmt/validate/相关测试、private saved plan。审 create/update/delete/replace、RBAC、网络、成本；不混 fault start。 |
| 3. 前置部署/发现 | 只应用获批的同一 saved plan；核实资源/配置、RBAC 生效、Workspace discovery/exclusions 与真实 Pod/node/VMSS/实体匹配。保留已有安装/state；默认无 schedule/run。 |
| 4. 无故障基线 | 云端 AKS technical probes 或后续真实业务流量，独立 control/ledger/observer；确认实际配额/容量、retention/保护、采样、硬 deadline 与停止通知/独立恢复演练。 |
| 5. 显式单故障 | 再核对实际匹配范围和运行授权，operator 显式启动一个已审 Scenario/Action 或获批 native/simulation。禁止 Terraform provisioner/默认 pipeline/REST apply 自动启动；不得遇错自动加压、重启、failover 或修权限。 |
| 6. 故障确认/观察 | 关联 Chaos/服务 operation、guest/Kubernetes events、实际协议/资源指标，记录 injection→impact→alert→decision；无命中/未达强度/Skipped 是缺证据，不是通过。 |
| 7. 停止/恢复 | 达阈值即独立通知并停止；Continuous/Cancelable 验证实际效果消失。Discrete 或进行中的 transition 按已批准 recovery，不承诺取消可 undo、不发竞争 failover。恢复原实体/网络状态或明确接受新 primary，failback 另审。 |
| 8. 稳定恢复/清理 | 按 phase 逐窗口验证 health、协议/业务与技术数据，确认 HA/容量/backlog/规则无残留。private scoped plan 调查 drift，不自动纠正；只删本次 owned PID/规则/文件/Job/权限/临时资源，不 destroy 共享目标。 |
| 9. 报告 | 每 ID/variant/phase 给 Passed/Failed/Inconclusive/Blocked、中文依据、真实作用/恢复/限制与私有证据位置。记录 Future/Unselected，但不填 Passed；infra 与 business 分栏。 |

无当前 Workspace Action 的 case 不执行旧 `chaos run` 样例来冒充 Chaos Studio 原生测试；先完成单独机制/权限/停止恢复评审，明确标 native/simulation。一个组合模板中的多个 Action 必须拆成初始单故障，不能借模板扩大范围。

### Pre-run gate

1. Confirm approved targets, affected users/data, time window, exposure limit, on-call operator, and recovery permissions.
2. Validate baseline, backup/replication health, private connectivity, remaining capacity, and absence of conflicting maintenance or experiments.
3. Review the resolved Workspace resource list and excluded list against the explicit allowlist. Dynamic discovery is not authorization. Require exact entity parameters; never leave them empty to imply all entities.
4. Verify Action/API/region/SKU eligibility and parameters. Unknown support is PendingVerification/PendingDesign; an unselected matching target is AwaitingTarget; unhealthy HA is PendingPrerequisite until recovered. Do not start. Record Blocked only for an evidenced incompatibility or reproduced unresolved preflight failure, not every unfinished preparation task.
5. Separate deployer, Workspace runtime identity, experiment operator, and application workload identities.
6. Derive custom least-privilege permissions from Scenario validation output. Assign only on approved targets; do not use subscription-level Contributor/Owner or automatically invoke permission-fixing operations.
7. Verify a tested cleanup/recovery procedure before fault start. Restore capacity includes the source of truth under cache misses and the consumer capacity required to drain messaging backlog.
8. Prevent Terraform/GitOps from correcting only the intentional temporary fault state during the authorized window; do not disable unrelated controllers or add broad permanent `ignore_changes`.
9. Rehearse the independent monitor and operator handoff: inject a harmless synthetic threshold breach or evidence silence, prove the signal reaches the operator within the agreed decision budget, and verify recovery access outside the target path. A script mounted in a ConfigMap is not an operational stop path.
10. Freeze the maximum actual affected set: resource IDs, pod/node selection, entity names and indirect dependencies such as geo-linked caches and pod sidecars. Configuration validation alone cannot attest dynamic pod/VMSS instance membership.

Use [resource targeting and validation][targeting] and [least-privilege role guidance][leastpriv]. Recommended catalog roles such as Contributor are references, not the default authorization policy.

### Proposed immediate stop/escalation conditions

- Any unapproved target or unaffected control flow is impacted.
- Any lost acknowledged durable record, duplicate business effect, broken transaction invariant, or unexpected corruption.
- Any unexplained success acknowledgment for failed/non-durable work.
- Control-flow success falls below 99% for 60 seconds, or p95 exceeds 2x baseline for 60 seconds.
- Retry calls exceed 3x baseline attempt rate for 30 seconds.
- Application/backing-store CPU or memory exceeds 80%, or connection use exceeds 80% of its verified limit, for 60 seconds.
- Test Service Bus backlog reaches 5,000 messages or 70% of approved entity capacity, whichever is reached first.
- Event Hubs/RocketMQ lag or retained work approaches its approved replay/retention/storage limit; define numeric per-partition/time/bytes caps before those cases. Do not apply the Service Bus count blindly.
- Recovery/observability access is lost, or the approved window/budget is exceeded.

Tune thresholds before authorization. Dependency-specific expected failures are not automatically a reason to abort a hard-outage test; loss of containment, integrity, or recovery access is.

Stop authority is the independent operator, informed by application/service evidence and the monitor. The current availability evaluator uses sample-count windows, silence/monitor budgets and optional latency/consecutive-failure thresholds; it does **not** implement every time-based rule above, evaluate CPU/backlog/integrity, cancel a run, or restore resources. Define cadence and maximum detection latency, map each rule to a proven observer/owner, and treat stale/missing evidence as Inconclusive plus stop/escalation. Do not describe the evaluator's limited `Passed` signal as a case pass.

For Continuous/Cancelable faults, stop the run and remove the effect, then verify actual recovery. For Discrete or in-progress service-native transitions, stop further injection and escalate to the recovery runbook; do not assume cancellation reverses a restart, flush, unlink, or failover. Do not issue a competing failover while one is still in progress.

### Recovery completion gate

- Fault/proxy/hook removed; actual connectivity verified, not merely a successful control-plane response.
- Original entity states restored, or new primary state deliberately accepted.
- HA/replication healthy; cache warmed; messaging backlog and DLQ reconciled.
- For `phase=infra`, §0.3 technical health/read/write and control criteria pass every recovery window with all attempted/ack/unknown IDs reconciled. For `phase=business`, the agreed business SLO/invariants pass for 10 minutes. Do not substitute either phase for the other.
- No unexpected drift; after approved recovery, inspect a correctly scoped Terraform plan privately. Do not apply it automatically to force the old topology.
- Clean up only owned test resources and assignments; retain required evidence privately. Never use `terraform destroy` as fault cancellation or business recovery.

## 8. Dependency-ordered delivery and execution waves

### Implementation tasks

These consolidate the original T0-T8 and follow-up I0-I7 without treating already-installed infrastructure as missing. Owners are functional roles, not assumed named people. Agree a responsible operator before cloud work.

| ID / owner | Prerequisites | Bounded deliverable | Exit gate |
| --- | --- | --- | --- |
| T0 / application + platform owner | None | Private case/variant/phase/target/state manifest, §0.3 technical contract or later actual business flow/SLO/RTO/RPO, eligibility, cost/window and recovery approvals. | Each selected case has a qualified scope/contract or a specific preparation status/evidenced incompatibility; no dependency on unselected business cases. |
| T1 / Terraform owner | T0 | Preserve existing platform/cluster/Chaos state mapping; check applicable old-environment migration and current locked schema/plan. | No duplicate ownership, unexpected platform changes, widening RBAC or unreviewed replacement. Bootstrap/migration only if independently required and authorized. |
| T2 / application + evidence owner | T0; approved control/HA prerequisites for its case | Technical canary/control, bounded protocol flows, independent ledgers, phase sampling and private evidence retention; later application adapters for business phase. Finish monitor/stop transport/operator handoff. | Authorized no-fault baseline meets the selected phase's contract; silence/notification rehearsal and independent recovery pass. Default Jobs remain off. |
| T3 / Chaos configuration owner | T1 | Validate selected existing service-direct contracts/parameters/target filters; derive exact Action permissions through validation, review grant plan, revalidate after propagation. | Resolved/excluded resources match manifest and effective rights are usable; no permission auto-repair, no run. T2 is not a prerequisite to author configuration. |
| T4 / AKS operator | T1, target selection/namespace contract from T0 | Reference and recheck installed extension/connection/federation/operator ownership; review architecture/image/admission/network cleanup and pod definitions. | Installation/support evidence refreshed; no duplicate install. Runtime qualification waits for T2/T5; network faults independently gated. |
| T5 / operator + application owner | T2, applicable T3 or T4 | Select one eligible case/variant/phase, review deployment/traffic/run/recovery authorization, then execute bounded cloud qualification. | Intended impact, containment, phase-specific criteria, integrity and sustained recovery evidenced; Failed/Inconclusive/Blocked are explicit, not completion-by-count. |
| T6 / relevant service owner | Clean recovery of relevant T5, T0 for expanded targets | Expand client/pod/entity/HA/node cases independently; native restore/destructive/DR/agent branches only with additional support/cost/ownership review. | Per-case evidence and approvals; no automatic escalation, repeated destructive actions or multi-fault overlap. |
| T7 / evidence + Terraform owner | Each executed T5/T6 run | Reconcile all operations, review private drift, remove only approved temporary resources, classify/report gaps and regression set. | Recovery and retained report complete; any remaining drift/data unknowns have an explicit owner and next action. |

Add focused constraint tests with configuration changes and behavior tests with measurement/client changes, not at the end. Use existing fixed-version validation-only CI; formatting, backend-disabled readonly init when needed, validate, targeted mocks/unit checks, TFLint and policy scanning are static evidence. Review applicable failures without global suppressions. Real apply tests, saved cloud plans, deployment and fault runs each need the relevant separate authorization.

T1 and T2 implementation can progress after T0, but cloud baseline qualification waits for that case's required controls/HA/evidence resources. Service-direct T3 and pod T4 are separate branches; private pod compatibility or blocked geo cases must not block eligible client-path/service-direct cases. The [implementation batch plan](./chaos-studio-implementation-plan.md) tracks engineering work only; this document defines cases and acceptance.

### Execution waves

| Wave | Work | Exit condition |
| --- | --- | --- |
| 0: No fault | Case-specific T0-T4, approved HA/control prerequisites, technical baseline, independent ledgers, stop/recovery rehearsal. | Each case is qualified or has explicit pending preparation/evidenced Blocked status; lack of a prerequisite does not certify it or prevent unrelated eligible cases. |
| 1: Minimal impact | Choose one eligible A-01/C-01/S-01, dedicated B-01/H-01 or qualified K-01; then other independently selected client/technical cases. | Actual cloud impact/control/integrity/recovery under §0.3; pure connectivity without injection cannot pass a fault case. Business adapters are not this phase's prerequisite. |
| 2: Entity/HA recovery | C-02/C-04/C-05 where applicable; M-02/M-01/P-01, R-02 then R-01/R-03, B-02/B-03/H-02/H-04; separately reviewed V-09. | Case-specific eligibility/real impact/restoration, including B-03 Discrete cleanup and VM guest/data impact. No automatic repeat/restart. |
| 3: Pressure/network/nodes | Qualified K-02–K-06, V-03–V-06/V-08, N-02–N-05/N-07 and P-02 after relevant low-impact recovery. I-01/N-06 remain PendingDesign until separate feasibility/containment review. | Agent/instance/image/rules/capacity/independent recovery; progressive intensity, real measured effect. Unmapped support is explicit; evidenced incompatibility stays Blocked, not fallback by default. |
| 4: Destructive/geo/special | Separately qualified V-07/V-10, R-04/A-02/S-04/S-02/S-03/H-05/H-06; M-04 requires a real dedicated read replica. Other PITR/geo/zone cases only if additionally selected. | Per-target data/replication/backup/role/cost/recovery and irreversible-impact authorization; no auto-creation to fill coverage. |
| 5: Later business/future | E-01/E-02/E-03 and original business-phase contracts; D/V broker cases only if selected; L/G future only with actual authorized targets. | Separate business SLO/invariants or future product qualification. Current infra pass does not close these cases; still one fault per run. |

Do not re-budget existing platform installation as new work. Cost review must include incremental capacity, traffic, retained evidence and temporary recovery fixtures, with a hard run/campaign ceiling and cleanup owner. No fixed price or cost approval is inferred from this document.

Start with one run per low-risk case. After fixes, seek three consecutive clean runs for repeatable low-risk cases. Destructive/DR repetition is separately reviewed rather than automatically repeated three times.

Budget items: HA database primary/standby, separate legacy/Managed Redis fixtures, eligible geo-replicated Redis members, Service Bus Premium secondary capacity, geo-redundant storage, private networking, AKS test Jobs, Chaos Studio, and monitoring retention. Exact estimates depend on region, SKU, data size, and duration; no cost approval is assumed.

Repeat the agreed low-risk regression set after client/SDK/retry/network changes; schedule recovery/DR reviews at least quarterly or according to business risk. Coverage percentage is informational, not a global pass gate.

## 9. Evidence and result classification

For each run, capture privately:

- Case ID, hypothesis, authorization reference, exact resolved targets, API/Action versions, parameters, identities, and fixture configuration.
- Baseline, traffic volume, fault-impact evidence, unaffected-control results, timeline, and recovery actions.
- Business success/latency, retry amplification, pools/connections, Kubernetes events, service metrics/health, and alerts.
- Data/message reconciliation, hashes/invariants, lost/duplicate counts, RTO/RPO, backlog and warm-up results.
- Chaos report plus independent application evidence; recovery/drift checks; limitations and next action.

### Required private case manifest and report

Use one stable case key plus a unique private run reference; retain the existing IDs below rather than renumbering PaaS cases. All fields are required for selected cases; state a specific non-applicability or blocker instead of leaving an empty value.

| Group | Required fields |
| --- | --- |
| Identity and scope | Case ID/variant, hypothesis, flow/SDK version, configuration commit and working-tree changes, environment/state owner, authorization reference, operator/contact held privately, exact direct/indirect targets and exclusions. |
| Mechanism | Simulation/service-direct/extension/native drill, Workspace region, Action/API versions, complete verified parameters, actual entity/pod/node set, intensity, exposure and maximum impact. |
| Phase contract | `infra`: §0.3 technical workload, health/read/write/integrity, per-window samples, deadlines/retries, restoration budget and retention. `business`: actual flow, durable acceptance, business SLO/RTO/RPO and invariant/idempotency/consistency. Explicitly mark deferred business fields, not silent omissions or fabricated pass. |
| Safety and restoration | Numeric thresholds with observer/detection budget/owner, independent recovery path, prior entity/topology states, backup/replication readiness, exact authorized stop/recovery/cleanup actions, cost and time ceiling. |
| Observations | UTC wall-clock timeline plus monotonic elapsed measurements, actual fault impact, control and target metrics, raw sample counts, alert/stop handoff, unknown/ack IDs, reconciliation and recovery/drift evidence. |
| Decision | Passed/Failed/Inconclusive/Blocked, Chinese explanation, evidence scope/limitations, follow-up owner, evidence location/hash/retention and explicit unresolved issues. |

Store ledgers outside the faulted dependency and canary lifecycle; test restart must not erase the acknowledgment truth source. Reconcile attempted, acknowledged, unknown, persisted, consumed and failed IDs by their business acceptance contract; retry counts are not unique operation counts. Do not log payload secrets or tokenized endpoints. Redact resource/registry names, contexts, private addresses, tenant/subscription and run/request IDs, personal contacts and credentials from public reports.

### Case-to-mechanism traceability

| Case family | Current preparation path | Acceptance still required |
| --- | --- | --- |
| C-01-C-05, A-01/A-03, R-03, S-01/S-02, B-04, H-03, D-01 | Application hooks/proxies/protocol clients; Terraform can prepare Jobs/fixtures only. H-03 may use K-01 after pod qualification. | Actual selected-path impact, deadlines/idempotency, independent ledgers and recovery; not service outage proof. |
| M-01/M-02, P-01/P-02, R-01/R-02, A-02/A-04 | Allowlisted service-direct definitions and existing/approved fixtures. | HA/cache/product eligibility, exact permissions, destructive/linked scope and data recovery. |
| B-01-B-03, H-01/H-02 | Allowlisted explicit entity state definitions. | Actual send/receive behavior, prior-state restoration, ledgers/retention and backlog drain. |
| S-03, D-02 | Allowlisted account-wide/region definitions; default single-region fixtures insufficient. | Geo/topology/schema/private access and distinct DR approval; not container-scoped or full-region loss proof. |
| M-03/P-03/S-04/B-05 | Native restore/protection/promotion runbooks; not supplied by a Chaos Action here. | Isolated recovery, RTO/RPO, data/auth/network and re-protection; no source replacement. |
| K-01-K-05 | Typed pod definitions plus operator-owned extension references. | Actual target match, private/architecture/image/admission compatibility and effect removal. |
| N-01/V-01 | Allowlisted VMSS shutdown/VM restart. | Real instance/broker impact, spare capacity/storage, message ledgers and workload recovery. |
| V-02 | Unselected broker business branch; single-VM pressure mechanisms exist under V-03/V-04. | VM managed identity/public outbound/OS, bounded pressure and separately selected broker durability qualification; native execution installs and retains its agent. |
| M-04/R-04/H-04-H-06/K-06 | Dedicated replica/client path, native flush/geo drill, consumer pause, progressive memory simulation. | Exact actual support/targets/data/retention/ownership and independent cleanup; do not conflate standby, partial-key invalidation, metadata-only DR or fixed memory pressure. |
| V-03-V-10/N-02-N-07/I-01 | Qualified compute agent/native action or separately reviewed scoped simulation/native drill. | VM/node/guest/agent/PID/volume/rule/mesh boundaries, actual effect and independent recovery; node-wide support not implied by Pod faults. |
| L-01-L-03/G-01-G-03 | Future only; no current target. | Actual product/target/probe/routing and separately qualified mechanism/authorization; do not fault AKS-managed LB. |
| E-01-E-03 | Actual multi-dependency application with one previously qualified fault. | Entire flow invariants, downstream headroom and durable eventual effects. |

These are preparation paths, not a claim that any case has run. Report declared/installed/qualified/accepted evidence separately per selected case. Unselected optional cases are out of campaign scope with a reason, not Passed. Selected cases missing prerequisites retain the specific §0.1 preparation status and `execution=NotRun`; reserve Blocked for evidenced incompatibility or reproduced unresolved preflight failure. Coverage percentage may use a fixed, disclosed selected-case denominator, but never turns pending, skipped or blocked cases into success.

| Result | Meaning |
| --- | --- |
| Passed | Actual intended fault affected the approved target/traffic; the selected `infra` or `business` phase's criteria and integrity met; restoration verified. Always record phase; infra pass is not full application resilience. |
| Failed | Fault ran but a required criterion failed, containment was violated, or recovery failed. |
| Inconclusive | Fault missed real traffic, evidence was insufficient, or the run was skipped without proving resilience. |
| Blocked | The current selected target/mechanism has an evidenced incompatibility or reproduced unresolved preflight failure; fault was not executed. Include scope, evidence and remediation. Ordinary missing configuration/verification/authorization is a preparation status with `execution=NotRun`, not an automatic Blocked verdict. Existing full-phase runner rejection results retain their own evidence and safety gates. |

Include a Chinese explanation of the evidence or blocker. A Chaos `Succeeded` is not an infra or business Passed. Static Terraform validation, plan-only tests, Ready pods, simulated-impact configuration and local probes are not cloud fault acceptance.

**Historical evidence for the original consolidation:** Repository configuration and official Workspaces catalog, targeting/ARM semantics, AKS node/extension guidance, Managed Redis geo-replication and Storage/Service Bus recovery documentation were reviewed without cloud mutation. Subsequent native discovery, reviewed configuration deployment, current metadata and validation evidence are recorded in §0.5; this historical paragraph does not override them. No fault, traffic or cloud recovery execution is claimed by this document. Documentation checks do not establish runtime Passed.

## 10. Decisions and completion checklist

The draft proposes the following; change them during review:

1. Freeze selected product/case variants/phases under §0, beginning with one eligible infra case. Distinguish both Redis products, SQL HA/PITR, Blob-only results, Service Bus and Event Hubs; Cosmos/broker business remain unselected.
2. Reference existing approved isolated targets and ownership; confirm regions/SKUs/HA/private access and prerequisite evidence without re-provisioning.
3. Confirm phase-specific technical or business thresholds, sampling, deadlines/retries, stop/recovery, cost and reconciliation before traffic authorization; deferred business SLO is not an extra infra gate.
4. Select one Wave 1 case and authorize its configuration/traffic/run/recovery separately. Destructive/account-wide/regional cases stay opt-in; deployment never authorizes execution.
5. Choose later recovery scope and exact data-loss/irreversible-operation contract; include flush/geo-linked scope, unlink/rejoin, PITR target, account failback and messaging regional promotion as applicable.
6. Assign operator/evidence/recovery owners, detection budget, cost ceiling, maintenance window and privately retained results.

After review, the next deliverable is implementation-ready case/runbook configuration and a reviewed deployment plan, not immediate fault execution.

### Review corrections incorporated

- Replaced contradictory historical inventories/provider blockers with current source plus clearly labeled prior installation evidence; no historical check is silently re-certified.
- Preserved all original 43 case IDs; added 27 distinct definitions and mapped all 39 supplied scenarios, including future LB/Gateway, unsupported node/mesh branches and separate infra/broker/business phases.
- Separated official Action support from the repository's allowlist, extension IDs, agent/native drills and client-path simulations.
- Made application success, sampling, unknown writes, RTO/RPO and sustained recovery measurable; limited HTTPS/availability-stop claims to their actual scope.
- Merged dependency ordering, ownership/state/migration, exact RBAC/target filtering, stop/recovery and private evidence into one acceptance contract.

### Campaign completion

The operator has conditionally authorized cloud testing and requested reports. Current selection is §0: infra-first, Cosmos/broker business unselected, LB/Gateway future. Each selected ID/variant/phase needs real fault/impact/integrity/recovery evidence; a full business-success report waits for the later business phase. No static/reference-client or platform-health evidence completes the campaign.

- [ ] Selected-case manifest, owners, support/identity/ownership and approvals are complete.
- [ ] Relevant current static/policy/plan checks are recorded separately from cloud evidence; no unexpected delete/replace/network/RBAC expansion.
- [ ] No-fault baseline for the selected phase and independent stop/recovery rehearsal are proven in cloud AKS.
- [ ] Each selected run has actual impact/containment, phase-specific technical/business and data evidence, and an honest verdict.
- [ ] Fault effects removed; healthy topology/capacity, reconciled data/backlog and sustained phase-specific recovery verified.
- [ ] Private post-recovery drift reviewed; only approved owned temporary resources cleaned up; evidence retained.
- [ ] Failed/Blocked/Inconclusive and unselected coverage gaps have reasons/owners; no claim that the entire matrix is certified.

This checklist is a development/operational evidence gate, not an extra customer sign-off requirement. This documentation merge completes only the planning deliverable.

## Official references

The Action catalog, Workspaces overview/targeting/ARM reference and least-privilege guidance, AKS node/extension and parameter reference, Cosmos DB reliability, Managed Redis geo-replication and Storage/Service Bus Geo-Replication pages were rechecked on **2026-11-23**. Other service background references below were carried forward from the original 2026-11-20 review and must be refreshed for selected cases; documentation support is never live subscription qualification.

- [Well-Architected reliability testing][waf]
- [Chaos Studio Workspaces overview][workspaces]
- [Workspaces supported resources and Action catalog][catalog]
- [Workspace resource targeting and validation][targeting]
- [Workspace least-privilege roles][leastpriv]
- [Workspace Scenario ARM/AzAPI schema][scenario-schema]
- [AKS extension requirements and known issues][aks-extension]
- [AKS extension installation and parameter reference][aks-install]
- [AKS node/VMSS testing][aks-nodes]
- [Cosmos DB reliability and regional recovery][cosmos-reliability]
- [MySQL Flexible Server HA][mysql-ha]
- [MySQL Flexible Server backup and restore][mysql-backup]
- [PostgreSQL Flexible Server HA][pg-ha]
- [PostgreSQL Flexible Server backup and restore][pg-backup]
- [Azure Cache for Redis reboot/flush administration][cache-admin]
- [Azure Managed Redis architecture best practices][amr-waf]
- [Azure Managed Redis active geo-replication and force-unlink][amr-geo]
- [Storage DR planning and support restrictions][storage-dr]
- [Storage customer-managed planned failover][storage-planned]
- [Storage failover initiation prerequisites][storage-start]
- [Service Bus message transfer, locks, and settlement][sb-locks]
- [Service Bus Geo-Replication][sb-georep]
- [Service Bus Geo-Disaster Recovery][sb-geodr]
- [Event Hubs metadata-only Geo-DR][eh-geodr]
- [Event Hubs data Geo-Replication][eh-georep]

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
