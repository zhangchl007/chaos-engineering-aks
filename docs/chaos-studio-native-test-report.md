# Chaos Studio 原生测试报告

**日期：** 2026-11-23，时间为 UTC+08:00。

**原生运行窗口：** 首轮 10:16:27–10:50:48；项目代码重跑 11:24:31–11:55:14。重跑结果见 §7，private AKS 当前验证边界见 §8。

**范围：** 已批准测试资源组中的 MySQL、PostgreSQL、Legacy Redis、Service Bus、Event Hubs，五个明确目标资源；消息故障进一步限定一个既有 queue / hub。真实资源名、订阅、tenant、端点及 run/request IDs 仅保留私有。

## 1. 结论与证据层级

- **实际执行9项原生测试，9个 run / 9个单 Action 均为 `Succeeded`**；不是仅执行 Validate，也没有用本地 mock 替代故障。
- **7项管理面影响/恢复检查为 Passed**：观察到目标状态变化，随后恢复原消息实体 Active 或数据库 Ready / HA Healthy，Resource Health 最终 Available。
- **2项 Redis 影响检查为 Inconclusive**：原生重启动作成功，但采样期间实例 provisioning state 一直为 Succeeded，未独立观察节点重启、连接中断或副本重新加入。不能把8–9秒的 Scenario 运行时间当作重启耗时或服务中断时长。
- 收尾检查五个目标均为 Resource Health Available；MySQL / PostgreSQL 为 Ready / HA Healthy，queue / hub 为 Active，Workspace 没有活动运行。**private AKS 保持开启，未执行 VM、节点、Pod 或共享网络故障。**
- **完整 infra / business 韧性结论均为 Inconclusive（未验证）**：本轮未发送 SDK/业务流量、未运行事务/消息账本及数据完整性检查，也未完成协议恢复、请求成功率、延迟、RTO/RPO 或持续业务恢复验收。原生 Succeeded、管理面 Passed、平台 Available 均不代表业务 Passed。

本报告是[统一70项用例清单](./chaos-test-and-coverage-plan.md)的本次执行记录，不新增另一套用例定义。§2覆盖9项已执行用例，§5覆盖其余61项；不宣称70项已经通过。

**最新更新：** §1–§6 保留首轮证据。随后直接用当前项目代码重跑同样9项，新增9个 run / Action 均 Succeeded、7项管理面 Passed、Redis 两项 Inconclusive，完整业务仍未验证。AKS 原生配置验证通过，但还未启动节点/Pod故障，不将其算作实际测试通过。

## 2. 已执行用例

每项只有一个 Action、一个明确目标资源；执行前重新检查配置参数/目标/排除、原生 Validate、实际解析目标、无并行运行、基线与 Resource Health。表中秒数为 Azure run 起止时间差，**不是实际 outage/RTO**。

| Case ID | 原生操作 / 参数 | 运行时间 | Run / Action | 实际观察与收尾 | 管理面影响/恢复结果 |
| --- | --- | --- | --- | --- | --- |
| B-01 | Service Bus queue `SendDisabled`，1分钟 | 10:16:27–10:17:38，71秒 | Succeeded / Succeeded | Active → SendDisabled → Active；namespace Resource Health Available | Passed；未验证 producer 重试/消息完整性 |
| B-02 | Service Bus queue `ReceiveDisabled`，1分钟 | 10:19:30–10:20:40，70秒 | Succeeded / Succeeded | Active → ReceiveDisabled → Active；namespace Resource Health Available | Passed；未验证 PeekLock、settlement、DLQ |
| H-01 | Event Hub `SendDisabled`，1分钟 | 10:22:17–10:23:26，69秒 | Succeeded / Succeeded | Active → SendDisabled → Active；namespace Resource Health Available | Passed；未验证 producer ack/unknown |
| H-02 | Event Hub `Disabled`，1分钟 | 10:25:00–10:26:12，72秒 | Succeeded / Succeeded | Active → Disabled → Active；namespace Resource Health Available | Passed；未验证 consumer checkpoint/replay |
| M-02 | MySQL restart，Discrete；结构 duration 为1分钟 | 10:27:47–10:31:44，237秒 | Succeeded / Succeeded | Ready → Restarting → Ready，HA Healthy；primary zone 1 → 3；Resource Health Available | Passed（管理面），但中途存在观测断档；未验证事务/已确认数据 |
| P-01 | PostgreSQL `PlannedFailover`，`RestoreOnStop=false`，不跳过不合格服务器 | 10:33:36–10:42:30，535秒 | Succeeded / Succeeded | Ready → Updating → Ready，期间 HA RecreatingStandby，最终 Healthy；Resource Health 首次收尾 Unavailable，复核后 Available | Passed（管理面恢复）；SameZone 不证明 zone-loss；未验证数据库协议/数据 |
| M-01 | MySQL HA failover，`RestoreOnStop=false`，1分钟 | 10:45:55–10:47:04，69秒 | Succeeded / Succeeded | Ready → Updating → Ready，HA Healthy；primary zone 3 → 1；Resource Health Available | Passed（管理面）；未验证未知 commit、事务不变量或 RPO |
| R-02 | Legacy Redis `SecondaryNode` reboot，Discrete | 10:48:42–10:48:51，9秒 | Succeeded / Succeeded | provisioning state 始终 Succeeded；Resource Health Available | Inconclusive：副本真实重启/重新加入未独立核验 |
| R-01 | Legacy Redis `PrimaryNode` reboot，Discrete | 10:50:40–10:50:48，8秒 | Succeeded / Succeeded | provisioning state 始终 Succeeded；Resource Health Available | Inconclusive：primary 重启/连接中断/缓存写入完整性未独立核验 |

所有已执行项的完整 infra/business 结果均为 **Inconclusive：缺少该层所需证据**。消息故障没有被当作区域故障，Redis reboot 没有被当作 flush 或 Managed Redis reboot。

## 3. 暂停、恢复与审计

### 3.1 两次执行流程暂停

| 情况 | 实际处理与结论 |
| --- | --- |
| MySQL 已接受 Execute 后，ARM 查询发生 transport timeout | 立即停止批次；使用已保存的同一 run ID 恢复观察，没有重复 Execute。原生 run / Action 最终 Succeeded，Ready / HA Healthy / Available 已核验。保留观测断档，不能声称全程连续观测或精确 outage 时间。 |
| PostgreSQL 原生 run 已 Succeeded，Ready / HA Healthy 已恢复，但首次 Resource Health 仍为 Unavailable | 未将 Unavailable 当 Healthy，也未继续下一故障。复核到 Available 后才继续；保留首次 Unavailable 与后续恢复证据。Resource Health 与管理面状态的短时不同步不被隐去。 |

后续只读 ARM GET 增加有限、显式记录的 transient retry；**Execute 不自动重试**。取消能力以实际区域 catalog 为准：消息状态与 HA failover 为 Cancelable，MySQL restart / Redis reboot 为 Discrete；取消 Scenario 不保证撤销已经开始的下层操作。未发生以重复重启、强制 failback、扩大权限或修改网络来掩盖失败的操作。

### 3.2 原生流程与停止边界

1. 使用既有 Workspace、单 Action Scenario 与 `approved-targets` Configuration；原生 Validate / Execute 均为官方无 body POST。
2. 串行执行；下一项必须等上一项原生动作结束及资源恢复核验。对 run/action 的实际目标检查排除列表，不仅看 HTTP 202。
3. ARM 约5秒间隔采样，实际间隔受请求延迟影响；MySQL 超时断档单独记录。没有新建测试应用、SDK Job、proxy、Chaos Mesh 或 guest 模拟。
4. 运行超过15分钟、恢复超过10分钟、目标越界或恢复不满足即停止批次；Cancelable 先取消，再仅恢复本次实体到原 Active 状态。Discrete 不靠 Cancel 撤销。本轮消息实体由原生动作恢复，未使用手工实体更新兜底。
5. 最后重新读取全部 run、五个目标 Resource Health、数据库 HA、消息实体与 AKS private 标志；无活动运行、消息实体 Active、数据库 Ready / HA Healthy、private AKS 为 true。

### 3.3 Azure Activity Log 快照

快照按五个明确目标资源及其子实体过滤，未发布真实标识。以下为已采集到的 Succeeded 管理操作：

| 操作 | 数量 / 解释 |
| --- | --- |
| `Microsoft.ServiceBus/namespaces/queues/write` | 4条，支持两次故障及两次恢复的控制面证据；具体状态以 ARM 采样为准 |
| `Microsoft.EventHub/namespaces/eventhubs/write` | 4条，支持两次故障及两次恢复的控制面证据 |
| `Microsoft.DBforMySQL/flexibleServers/restart/action` | 1条 |
| `Microsoft.DBforMySQL/flexibleServers/failover/action` | 1条 |
| `Microsoft.DBforPostgreSQL/flexibleServers/restart/action` | 1条；原生 planned failover 使用此 RP 操作，不能因此改称普通重启测试 |
| `Microsoft.Cache/redis/forceReboot/action` | 快照仅有1条 Succeeded；两次 Redis 运行的完整审计覆盖尚未确认，不能据此证明两个节点均已实际恢复 |

同时记录到 PostgreSQL Resource Health 激活/处理中/恢复事件。审计有发布延迟，缺少事件不是未执行或已成功的充分证据；成功事件也不替代协议/数据验收。

**配置持久化：** 故障恢复后，使用原 Chaos owning state 和完整私有输入 replan，`-detailed-exitcode=0`。这只证明 Chaos 配置栈无漂移，**不是整个 Platform state 的 plan 或数据完整性证明**。MySQL restart 后角色从 zone 1 切到3，随后独立 M-01 测试切回1；这是两项已记录测试，不是隐蔽的自动 failback。没有执行 Platform/Cluster apply 来纠正临时故障状态。

## 4. 本轮没有验证的内容

- 真实应用请求成功率、延迟、重试/超时、订单/库存事务不变量、ack/unknown 与唯一业务 effect。
- Redis 真实节点重启/复制恢复、cache-aside、版本/freshness、已确认缓存写入完整性。
- Service Bus producer/consumer ledger、PeekLock/settlement、重复效果、outstanding/DLQ；Event Hubs partition offsets、durable checkpoints、replay、retention 与一致效果。
- 十个连续一分钟业务恢复窗口、实际 RTO/RPO、故障是否命中真实业务流量。不得从管理面状态推导零丢失、全局顺序或 exactly-once。
- AKS Pod/node readiness、业务放置与剩余容量。只核对 private 标志，不能称 AKS 故障验证 Passed。

## 5. 其余61项：能力与本轮未运行原因

这些项统一为 `execution=NotRun`；准备状态与实际故障结论分开。待配置/待核验/待授权不是平台永久不支持。完整定义及安全约束继续以[统一用例清单](./chaos-test-and-coverage-plan.md#05-原生能力优先本轮执行与暂缓标注)为准。

### 5.1 原生能力存在，但安全前置/范围尚未满足（15项）

| Case ID | 原生能力 | 本轮状态 / 原因 |
| --- | --- | --- |
| P-02 | PostgreSQL forced failover | AwaitingAuthorization；已配置/Validated，但普通原生测试请求不自动扩大到 forced 模式及其恢复风险 |
| V-09 | 单 VM restart | PendingVerification；须核验既有 broker / 间接消费者的中断许可、guest 与恢复，不把平台 Available 当所有服务就绪 |
| N-07 | 精确 User VMSS / zone shutdown | PendingVerification；配置已 Validated，但当前一节点损失一半 User-pool 容量，workload/存储放置、剩余容量与恢复未核验；不以一个 VMSS 的解析数量代替实例数量 |
| V-03, V-04 | 单 VM CPU / memory pressure | PendingPrerequisite / PendingVerification；VM managed identity 缺失，public outbound、headroom、恢复待核验。原生运行会自动安装并保留 agent，不需手工预装 classic agent |
| K-01, K-02, K-03, K-04, K-05 | AKS extension Pod delete / CPU / memory / latency / loss | AwaitingTarget / PendingVerification；需私网操作端核验当前获授权 namespace AND labels / workload。private AKS 为官方未验证配置，不是明确不支持；没有故障化 System/控制 pods 或新建自定义应用补齐 |
| N-01 | zone 范围 VMSS shutdown | PendingConfiguration / AwaitingAuthorization；不是 N-07 单节点授权，不能扩大到整个 zone |
| N-02, N-03 | VMSS CPU / memory pressure | PendingDesign / PendingVerification；精确实例边界、agent 身份/出站及剩余容量待确认，不压整池或用 Pod hog 冒充 |
| B-03 | Service Bus topic / subscription state | AwaitingTarget / PendingConfiguration；尚无独立合格 topic/subscription 配置及相应 Discrete 恢复许可；queue 结果不能替代 |
| A-02 | Managed Redis flush database | PendingVerification / AwaitingAuthorization；数据库独占、完全可重建与不可撤销删除/恢复未确认，不默认清库 |

### 5.2 当前目标存在已证实不兼容（2项）

| Case ID | 状态 | 证据 / 边界 |
| --- | --- | --- |
| S-03 | Blocked | 当前 Storage 为 Standard_ZRS，没有 geo planned failover 前置；不为测试迁移 GRS/GZRS |
| A-04 | Blocked | 当前 Managed Redis 数据库没有 geo-replication links，没有可 force-unlink 对象；不自动创建 geo 伙伴或修改拓扑 |

### 5.3 当前尚未确认等价 Chaos Studio 原生动作（25项）

“未确认”指当前资源模型、实际目标与精确故障语义；不是断言整个 Azure 产品或所有区域永久不支持，也不把其它动作改名冒充。

| Case ID | 暂不具备本轮等价原生能力的内容 |
| --- | --- |
| C-01, C-02, C-03, C-04, C-05 | 单依赖连接 blackout、延迟、未知确认、局部 DNS、协议匹配 throttle；共享 NSG、Pod-wide 故障不自动等价 |
| M-04 | 独立 read replica 不可用；HA standby 不等于 read replica，实际独立目标也未确认 |
| R-03, R-04 | Legacy Redis 有限 key invalidation / 全库 flush 的对应 Workspace 动作；不能套 Managed Redis Action |
| A-01, A-03 | Managed Redis 单客户端断连 / 区域客户端重定向；flush/unlink 不等价 |
| S-01, S-02 | Blob interrupted transfer / 客户端 secondary-read fallback；当前 ZRS 也无 RA-GRS/RA-GZRS secondary 前置 |
| B-04, H-03, H-04 | commit/settlement/checkpoint 间隙或专用 consumer pause；状态禁用不证明这些时序 |
| K-06 | 逐步内存泄漏模型；固定 memory hog 不等价 |
| V-05, V-06, V-07, V-08, V-10 | VM 精确目的路径 latency/loss、专用卷 exhaustion/IO、精确 guest 进程终止 |
| N-04, N-05, N-06 | 精确 node loss/latency/API partition；Pod-only 故障不证明 node-wide，不改共享 NSG/API 路由 |
| I-01 | ASM/Istio control/data partition；实际 mesh 目标及精确机制未确认，不安装 mesh 补齐 |

### 5.4 服务专项、未选择或未来范围（19项）

| Case ID | 状态 / 原因 |
| --- | --- |
| M-03, P-03, S-04, B-05, H-05, H-06 | Deferred：PITR、Blob protection、regional / Geo-DR / Geo-Replication 等服务原生专项，不是本轮已确认的 Chaos Studio Action；独立资源生命周期/数据恢复授权尚未完成 |
| D-01, D-02 | Unselected：Cosmos 本轮不选；D-02 虽有 offline-region Action，不扩展 region 补覆盖率 |
| V-01, V-02 | Unselected：RocketMQ 业务 durability 验收未选择，VM restart/pressure 不自动证明 broker/store 保证 |
| L-01, L-02, L-03, G-01, G-02, G-03 | Future：当前无获授权独立 LB/Gateway 目标；catalog LB admin-state 不证明所有 backend 网络/probe 语义，不故障化 AKS 托管 LB |
| E-01, E-02, E-03 | Deferred：完整多依赖业务流/SLO/不变量未接入，不是本轮原生控制面测试的新增前置 |

## 6. 私有证据与可审计性

原始 run/action 快照、明确参数/目标、Validate、ARM 采样、Resource Health、恢复、Activity Log 与配置 replan 已统一保存到项目 Git 忽略目录 `local-state/dev/chaos-testing/`，九项 journals 位于 `native-test-runs/`，迁移前后 SHA256 不变。操作代码与全部步骤见[测试 runbook](./terraform-deployment-runbook.md#chaos-test-operations)。没有把原始日志、state/plan、kubeconfig、订阅/tenant/run/request IDs 或凭据写入本报告。

以下 SHA256 对应各最终私有运行记录，便于对照本报告版本；摘要不替代原始证据复核。

| 记录 | SHA256 |
| --- | --- |
| B-01 | `148c8f9ca1f6c358b5c1fa5cf2430e016f12639266fb526914ac94d6b96c5fb6` |
| B-02 | `72cf3013d9eae47f761b99795715b3ce3916be922b2e686ef983b8582333354e` |
| H-01 | `980376b1b286bbdc4bc9bf71f26442223bdd5c9fc13a309c3b1567b473ab1d44` |
| H-02 | `a80ec619c91465829b5d6b1ece0bf4278a9b941dd50ece60e9eb8a6cb36d7a4b` |
| M-02 | `7a5bd7d6fb58a4e4eafd8d38309d8c7e0d419e18266f23cacaa614d0d29dee5f` |
| P-01 | `d3b7f392455f9fddb8f7e0ac8da4e7277b8d38ab47d4001dd2f8ab561ca97674` |
| M-01 | `68e0eb54e3d5d434b70228514991711162427f22c6aca2aae993b39d1828f414` |
| R-02 | `741c1311d51fcc2c3424b6bac5087f59eb19143e7e3363c2b1b62612dff6ca26` |
| R-01 | `b86e7059f892fab34852c8644fd918a622864d38fa5f77b5603df861f3535c5d` |

**下一阶段：** 如需完整韧性验收，在已有云端应用/指标上补齐协议、真实影响、独立数据/消息账本及持续恢复证据；Redis 先补真实节点/副本影响证据。其余场景只在目标、机制、安全前置与对应授权满足后执行，不以补足数量为目标。

## 7. 当前项目代码实际重跑结果

直接执行项目 `run_native_case.py --config-dir <本轮目录> --execute`，九项串行，沿用既有 Workspace/Scenarios/明确目标和一实体边界。完整输入、源代码 SHA256、原生验证、原始日志、journals 与收尾证据均在项目 Git 忽略目录 `local-state/dev/chaos-testing-rerun-20261123/`。没有使用会话内旧执行脚本，没有 SDK/模拟流量，没有修改部署身份、RBAC、网络或平台资源。

| Case ID | 原生 run 起止（UTC+08:00） | 实际秒数 | Run / Action | 管理面结果 |
| --- | --- | --- | --- | --- |
| B-01 | 11:24:31–11:25:46 | 76 | Succeeded / Succeeded | Passed，SendDisabled 后原 Active 恢复 |
| B-02 | 11:26:57–11:28:10 | 73 | Succeeded / Succeeded | Passed，ReceiveDisabled 后原 Active 恢复 |
| H-01 | 11:29:15–11:30:22 | 67 | Succeeded / Succeeded | Passed，SendDisabled 后原 Active 恢复 |
| H-02 | 11:32:01–11:33:10 | 70 | Succeeded / Succeeded | Passed，Disabled 后原 Active 恢复 |
| M-02 | 11:34:19–11:38:15 | 236 | Succeeded / Succeeded | Passed，数据库 Ready / HA Healthy / Available 恢复 |
| P-01 | 11:39:24–11:46:16 | 412 | Succeeded / Succeeded | Passed，Ready / HA Healthy；收尾 Resource Health Degraded 后核验 Available，未隐去滞后 |
| M-01 | 11:51:31–11:52:40 | 69 | Succeeded / Succeeded | Passed，数据库 Ready / HA Healthy / Available 恢复 |
| R-02 | 11:53:44–11:53:53 | 10 | Succeeded / Succeeded | Inconclusive，缺少独立副本重启/复制恢复证据 |
| R-01 | 11:55:04–11:55:14 | 10 | Succeeded / Succeeded | Inconclusive，缺少独立 primary 重启/连通恢复证据 |

秒数为 run 时间差四舍五入，不是 outage 或 RTO。两轮合计18个成功 run，仍只有9个用例被执行，不是18个不同用例。

**交互中断与恢复：** P-01 原生 run 已 Succeeded，但 Resource Health 仍 Degraded 时，控制端交互中断终止了批次。随后使用项目 `observe_native_run.py` 指定同一 cohort、同一原 run，继续核验到 Available；没有重发 PostgreSQL Execute。之后只执行尚未启动的 M-01/R-02/R-01。本轮没有自动取消或手工 queue/hub 状态恢复兜底。

**代码可行性：** 项目 validator 实时验证12/12配置通过；完整 Python 单元测试73项通过。直接使用项目 runner 完成9/9真实原生故障及恢复，项目 observer 完成同一 run 恢复观察，项目 summarizer 离线生成与原件一致的状态/秒数/hash。没有为通过测试修改源码或放宽 guards；这不认证未执行的 SDK、Pod、VMSS 或业务路径。

**最终云端复核：** 重新读取九个实际 run，均只有一个 Succeeded Action、一个预期资源；每个 Scenario 相对其执行前历史只新增一个 run，没有重复 Execute。五个 PaaS Resource Health Available；数据库 Ready / HA Healthy，queue/hub Active；Workspace 无活动运行；private AKS 标志仍 true。原 Chaos owning state、完整输入 replan 的 detailed exit code 为0，未 apply。

**审计快照：** 本轮目标范围内 Succeeded 操作：Service Bus queue write 4条、Event Hub write 4条、MySQL restart 1条、MySQL failover 1条、PostgreSQL restart（planned failover 下层操作）1条、Redis forceReboot 2条。完整覆盖不等于独立节点、协议或数据保证。

| Case ID | 本轮最终 journal SHA256 |
| --- | --- |
| B-01 | `db514d34e6c9425f414029e6715fa89eaf1658cf58b547e1acc6f8322a9549dc` |
| B-02 | `d656b801b2056ac83bdabd0d5928ea7db20f16a5c7bb5656fc81144871f3a168` |
| H-01 | `06ef6bd8f6493a2abf398f96b901f1017ca220b2cf92d6c925b0f6297af71d0f` |
| H-02 | `42353521f82cf62e44a1c4744aa96944c0accbc55020497cff64186c64f1ed99` |
| M-02 | `04af6bfacbd6bdb27c0cefde9d931553208daa89173a0a98209ae49d8c41723f` |
| P-01 | `348fcaa60c8080ca17ae7e4778f778795a28f6406d35c3115332742c3b76d3cb` |
| M-01 | `6be7cbb6efe02eba997d1b4734bb195282ead30dd8d85dac5dc804fde554a334` |
| R-02 | `521097df6a75c9319622fcc3af3cf82549cbc56e7b0a5664c845e3247c72fab1` |
| R-01 | `bb88c5fb6baa9a3e4e64b3f3a49c0a6c9fca3a8ac22630637fe24884b36a23c0` |

## 8. private AKS 原生测试当前状态

用户追加 AKS 测试要求后，重新核验 ARM / AKS MCP 元数据及既有监控，没有安装自定义测试应用、agent、mesh，没有开放 private API，也没有启用 AKS Run Command。

| 检查 | 当前结果与边界 |
| --- | --- |
| Private / 健康 | private=true，AKS provisioning Succeeded、Resource Health Available；是控制面证据，不是 Kubernetes Ready 或业务证据 |
| N-07 原生关联 | 已有精确 User VMSS / region / zone-2 配置，本轮原生 Validate Succeeded；System VMSS 显式排除 |
| 真实实例 | User 与 System 各两个实例，分别在 zone 2、3；当前 zone-2 User 选择匹配一个实例，不把一个 VMSS 当一个节点。损失该实例会减少一半 User-pool 容量 |
| 当前操作端 | 已确认 ARM/MCP 中集群与用户指定目标一致；无法解析 private AKS API。另按确切 cluster ID 找到唯一 private endpoint，其既有私网 TCP 路径也不可达；没有改 DNS/路由/公网，不启用已关闭的 AKS Run Command |
| 既有监控 | KubeNodeInventory / KubePodInventory 精确 cluster 范围近10分钟查询均返回0行；不能据此断言没有 workload 或所有节点 Ready |
| 实际故障 | **N-07、K-01–K-05 execution=NotRun / PendingVerification**；未核实当前 workload、存储/副本放置、控制/恢复组件所在节点与剩余容量，不能安全启动 shutdown/Pod故障 |

private cluster 本身不阻塞 service-direct VMSS Action；缺的是当前私网认证观察路径和动态安全证据。Pod extension 的 private-cluster preview 未验证状态也不等于明确不支持。需要已有获批准的私网执行端取得当前节点/Pod/放置和恢复证据后，才原生执行单 User-node / 明确 namespace AND labels 的 Pod测试；不把 Validate 写成实际故障 Passed，不自动新增临时身份或权限来绕过边界。

用户提供的 Portal 菜单内容仅用来确认目标，不视为授权安装 Periscope、启用日志或修改 API access security。本次未做这些变更，也没有在观察路径未核实时先执行节点/Pod故障。私有路由核查原件为本轮目录中的 `aks-private-route.private.json`。
