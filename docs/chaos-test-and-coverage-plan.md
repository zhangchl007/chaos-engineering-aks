# Azure 韧性测试场景清单（客户参考）

**核对日期：2026-11-23。** 本文涵盖当前设计的全部 **70 个场景**，按服务分类，明确哪些可以使用 Chaos Studio，哪些需要其他方式完成。

**依据说明：** 产品能力以各组附带的 **Microsoft Learn 官方链接**和区域动作目录为依据；“部分支持／待核验”是本项目的归类。实际配置见[第四节实时复核](#workspace-configuration-audit)，业务结果另见测试报告，三者不能混为一谈。

## 一、如何看“是否支持”

这里的 Chaos Studio 指**当前设计采用的 Workspaces / Scenarios，以及 AKS 扩展**，不包含旧版 Experiments（classic）。不能把某个旧版故障、任意自定义脚本或自动化 Runbook 算作当前模型的内置能力。

| 标识 | 含义 |
| --- | --- |
| **支持** | 官方已有对应故障动作；仍须满足目标区域、规格、权限及配置要求。 |
| **支持（预览）** | AKS 扩展已有对应能力，属于预览功能，不用于生产。 |
| **部分支持** | 故障注入可借用已有动作，但不能仅靠 Chaos Studio 完成该场景的时序控制或业务验证。 |
| **非原生** | 本次核对的官方动作目录及 AKS 扩展文档未列出该场景的专用内置动作，需客户端模拟、应用配合或服务自身恢复功能；不推断其他模型或未来版本也不支持。 |
| **待核验** | 有相关基础能力，但尚未确认能满足本设计的精确目标和隔离要求，不能写成已支持或永久不支持。 |

**注意：支持不等于当前环境可执行，更不等于已经测试通过。** 表中“非原生”也不表示对应 Azure 服务本身不具备恢复能力。

## 二、全部场景

<a id="service-vm"></a>
### 1. 虚拟机：8 项

官方依据：[计算类动作目录][cs-compute]。目录列出 CPU、物理内存压力及重启等能力，未列出本表要求的网络延迟、丢包、磁盘压力和 VM 进程终止专用动作。

| 编号 | 测试场景 | Chaos Studio | 当前限制或其他实现方式 |
| --- | --- | --- | --- |
| V-03 | CPU 高负载，验证服务是否降级及恢复 | **支持** | 使用 CPU 压力动作；需满足代理、身份及出站要求，从低强度开始，不默认满载。 |
| V-04 | 内存高负载，验证内存不足时的行为 | **支持** | 使用物理内存压力动作；不等于持续增长的真实内存泄漏。 |
| V-05 | 指定网络路径增加延迟 | **非原生** | 当前未确认对应 Workspaces 动作，需精确网络模拟；不影响管理和恢复链路。 |
| V-06 | 指定网络路径丢包 | **非原生** | 需网络模拟工具，限定目的地址及端口；与延迟分开测试。 |
| V-07 | 测试磁盘空间或文件数耗尽 | **非原生** | 需在专用可恢复测试卷上写入有限测试文件，不能填满系统盘或业务数据盘。 |
| V-08 | 磁盘读写压力，验证吞吐下降和超时 | **非原生** | 需受控磁盘压测工具，限制速率、文件、时长和费用。 |
| V-09 | 虚拟机重启，验证服务自动恢复 | **支持** | 已有重启动作；当前配置校验通过但未执行，需先核对全部消费者及恢复方法。 |
| V-10 | 单个应用进程终止，验证进程自动拉起 | **非原生** | 当前未确认 VM 精确进程终止动作；App Service 的进程终止能力不能直接套用到 VM。 |

<a id="service-pod"></a>
### 2. AKS 容器：6 项

官方依据：[AKS 扩展能力与限制][aks-extension]。官方明确列出删除、CPU、内存、网络延迟、网络丢包五类故障，并标注为预览。

| 编号 | 测试场景 | Chaos Studio | 当前限制或其他实现方式 |
| --- | --- | --- | --- |
| K-01 | 删除指定 Pod，验证副本补齐和服务恢复 | **支持（预览）** | 通过 AKS 扩展执行；限定命名空间和标签，不能只看新 Pod 创建成功。 |
| K-02 | Pod CPU 高负载 | **支持（预览）** | 通过扩展施加 CPU 压力；核对容器工具、资源限制及剩余容量。 |
| K-03 | Pod 固定内存压力，观察内存不足及重启 | **支持（预览）** | 通过扩展消耗内存；固定压力不等于逐步泄漏。 |
| K-04 | Pod 网络延迟 | **支持（预览）** | 影响该 Pod 共享网络的容器，包括边车；不等于只影响一个数据库连接。 |
| K-05 | Pod 网络丢包 | **支持（预览）** | 需足够流量证明真实丢包；结束后仍须检查连通性和网络残留。 |
| K-06 | Pod 内存持续增长，模拟内存泄漏 | **非原生** | 当前扩展仅确认固定内存压力；渐进泄漏需专用测试进程或应用配合。 |

**当前环境：** 扩展已有安装记录，但私有集群的观察连接、实际目标和恢复条件尚待确认，以上场景未完成实际故障验证。

<a id="service-node"></a>
### 3. AKS 节点与服务网格：8 项

官方依据：[计算类动作目录][cs-compute]、[AKS 节点测试指导][aks-nodes]、[网络动作目录][cs-network]。节点测试针对规模集，不能用 Pod 故障替代；精确隔离方案仍按本项目边界核验。

| 编号 | 测试场景 | Chaos Studio | 当前限制或其他实现方式 |
| --- | --- | --- | --- |
| N-01 | 同一可用区内的指定用户节点不可用 | **支持** | 使用节点对应的虚拟机规模集关闭动作；仅模拟这些节点丢失，不代表整个 Azure 可用区中断。 |
| N-02 | 单节点 CPU 高负载 | **支持** | 官方有规模集 CPU 压力能力；本项目精确节点选择、代理和容量条件尚未核验，不允许直接压整池。 |
| N-03 | 单节点内存高负载 | **支持** | 官方有规模集内存压力能力；当前单节点实施条件待核验，不能用 Pod 内存压力替代。 |
| N-04 | 单节点指定网络路径丢包 | **非原生** | 当前未确认对应节点级动作，需受控主机网络模拟；Pod 丢包不能替代。 |
| N-05 | 单节点指定网络路径延迟 | **非原生** | 需单节点网络模拟，保留独立恢复链路，不修改共享网络。 |
| N-06 | 单节点与 Kubernetes API Server 断连 | **待核验** | 有网络安全组规则基础动作，但精确隔离、影响范围及恢复方式未确认，当前不执行。 |
| N-07 | 仅一个用户节点不可用 | **支持** | 使用规模集关闭能力，但实际筛选必须恰好命中一个实例；当前配置校验通过、未运行，不能默认随机删除节点。 |
| I-01 | 服务网格代理与控制面断连 | **待核验** | 尚未确认等价动作、具体网格目标和隔离方法；普通 Pod 丢包不等价。 |

<a id="service-mysql"></a>
### 4. MySQL：4 项

官方依据：[数据库动作目录][cs-databases]列出 MySQL 故障转移与重启；[MySQL 备份恢复][mysql-backup]说明时间点恢复属于数据库服务自身能力。

| 编号 | 测试场景 | Chaos Studio | 当前限制或其他实现方式 |
| --- | --- | --- | --- |
| M-01 | 高可用主备切换 | **支持** | 已执行原生测试；需健康的高可用实例，事务和应用恢复仍需单独验证。 |
| M-02 | 数据库重启 | **支持** | 已执行原生测试；重启时长不等于应用恢复时间。 |
| M-03 | 误删或误更新后，恢复到指定时间点 | **非原生** | 使用 MySQL 时间点恢复功能，恢复到新实例，不覆盖源数据库。 |
| M-04 | 独立只读副本访问中断 | **待核验** | 需真实只读副本和精确隔离方法；高可用备用节点不能当作只读副本。 |

数据库断连、延迟、未知提交、DNS 和资源限制，另按第 11 节通用场景分别测试。

<a id="service-postgresql"></a>
### 5. PostgreSQL / PGSQL：3 项，另加 5 类通用测试

官方依据：[数据库动作目录][cs-databases]明确列出 PostgreSQL 故障转移的计划、强制两种模式；[PostgreSQL 高可用][pg-ha]及[备份恢复][pg-backup]说明主备与时间点恢复边界。

| 编号 | 测试场景 | Chaos Studio | 当前限制或其他实现方式 |
| --- | --- | --- | --- |
| P-01 | 计划高可用切换，验证事务和连接池恢复 | **支持** | 已执行计划切换；管理面已恢复，但事务完整性、连接池和业务恢复尚未验证。 |
| P-02 | 强制高可用切换，验证突发故障恢复 | **支持** | 原生动作支持强制模式；当前配置校验通过、尚未获执行授权，需单独评估风险。 |
| P-03 | 误删或误更新后，恢复到指定时间点 | **非原生** | 使用 PostgreSQL 时间点恢复功能，恢复到新隔离实例；核对恢复点数据及恢复耗时。 |

**PostgreSQL 还必须覆盖以下客户端测试，复用通用编号，不重复计入 70 项：**

| 通用编号 | PostgreSQL 测试内容 | Chaos Studio |
| --- | --- | --- |
| C-01.postgresql | 已有连接和新连接同时中断，验证超时、重试及连接池恢复 | **待核验**：网络阻断有基础动作，但本设计要求的单客户端、单依赖隔离尚未确认。 |
| C-02.postgresql | 数据库访问增加延迟，观察查询、提交及连接池等待 | **非原生**：需客户端路径模拟；Pod 整体延迟不等价。 |
| C-03.postgresql | 事务可能已经提交，但客户端未收到结果，验证是否重复写入 | **非原生**：需精确控制提交响应窗口，并按业务唯一编号核对。 |
| C-04.postgresql | 仅测试客户端的数据库域名解析失败，验证重新解析和重连 | **待核验**：阻断 DNS 有基础能力，但不能直接等价为单个域名、单个客户端的解析失败。 |
| C-05.postgresql | 模拟连接容量或驱动可重试错误，验证限流、排队和退避 | **非原生**：需匹配 PostgreSQL 驱动的模拟，不能用 HTTP 限流错误替代。 |

**边界说明：** 当前模块默认同可用区高可用、关闭异地冗余备份；同区切换不能证明跨可用区或跨区域容灾。当前 Workspaces 目录只确认 PostgreSQL 故障转移，不能将切换中的底层重启日志当作“普通重启测试已通过”。

<a id="service-legacy-redis"></a>
### 6. 两种 Redis：8 项

#### Azure Cache for Redis（旧产品）

官方依据：[缓存动作目录][cs-cache]、[旧版 Redis 重启说明][redis-admin]。官方明确区分主节点和副本重启及适用规格。

| 编号 | 测试场景 | Chaos Studio | 当前限制或其他实现方式 |
| --- | --- | --- | --- |
| R-01 | 主节点重启，验证连接切换和缓存降级 | **支持** | 已执行原生重启；缺独立节点、连接及恢复证据，不能宣称完整通过。 |
| R-02 | 副本节点重启，验证副本重新加入 | **支持** | 需有副本的规格；已执行原生动作，但副本恢复证据仍不足。 |
| R-03 | 少量热点缓存失效，验证回源和缓存击穿保护 | **非原生** | 由测试客户端使指定测试键失效，不使用全库清空替代。 |
| R-04 | 全数据库清空，验证缓存重建 | **非原生** | 当前未确认此产品的 Workspaces 清库动作；需数据面操作，仅限独占、可重建测试库。 |

<a id="service-managed-redis"></a>
#### Azure Managed Redis

官方依据：[缓存动作目录][cs-cache]列出清库和强制解除关联；[Managed Redis 异地复制说明][redis-geo]说明复制组范围及解除关联后的恢复要求。

| 编号 | 测试场景 | Chaos Studio | 当前限制或其他实现方式 |
| --- | --- | --- | --- |
| A-01 | 客户端无法访问缓存，验证降级和重连 | **待核验** | 对应通用断连测试；尚未确认满足集群客户端及单依赖边界的原生方案。 |
| A-02 | 清空数据库，验证回源和缓存回暖 | **支持** | 官方有清库动作；可能影响全部异地关联缓存，当前数据可重建性及删除授权未确认。 |
| A-03 | 一个区域的测试客户端不可达，切换到其他区域访问 | **非原生** | 需客户端隔离及应用端点重定向，不代表 Azure 区域中断。 |
| A-04 | 强制解除异地复制关联，验证拓扑恢复 | **支持** | 官方有解除关联动作；当前没有可操作的异地关联，暂不能执行。恢复可能需删除并重建受影响缓存，必须另行授权。 |

**两种产品不能混用动作。** 旧产品的主副本重启不能直接套到 Managed Redis；清库只允许处理可重建测试数据，不操作会话或唯一持久数据。

<a id="service-blob"></a>
### 7. Blob 存储：4 项

官方依据：[存储动作目录][cs-storage]仅列计划性故障转移；[计划切换说明][storage-planned]及[Blob 软删除恢复][blob-restore]分别说明区域切换、数据保护能力。

| 编号 | 测试场景 | Chaos Studio | 当前限制或其他实现方式 |
| --- | --- | --- | --- |
| S-01 | 上传、下载中断或响应丢失，验证重试及文件完整性 | **非原生** | 需客户端或传输模拟；核对内容摘要、长度、版本和重复上传。 |
| S-02 | 主访问路径异常时，切换到辅助区域只读 | **非原生** | 需存储服务的辅助只读能力及客户端切换；当前 ZRS 配置不满足条件。 |
| S-03 | 存储账户计划性区域故障转移 | **支持** | 官方有计划性切换动作；影响整个账户，当前 ZRS 不具备所需异地冗余条件。 |
| S-04 | 文件误删或覆盖后恢复 | **非原生** | 使用 Blob 软删除或版本恢复；不是 Chaos Studio 故障转移动作。 |

<a id="service-servicebus"></a>
### 8. Service Bus：5 项

官方依据：[消息动作目录][cs-messaging]列出队列、主题、订阅状态变更；[Service Bus 异地复制][sb-geo]区分数据复制与仅元数据灾备。

| 编号 | 测试场景 | Chaos Studio | 当前限制或其他实现方式 |
| --- | --- | --- | --- |
| B-01 | 队列禁止发送，验证生产者失败或持久排队 | **支持** | 已执行单队列状态变更，状态恢复已确认；消息及业务完整性尚未验证。 |
| B-02 | 队列禁止接收，验证消息积压和恢复消费 | **支持** | 已执行单队列状态变更；积压、重复消费及死信仍需验证。 |
| B-03 | 禁用主题或订阅，验证发布订阅影响 | **支持** | 官方有对应动作，主题和订阅分开测；当前目标待选，结束后需显式恢复原状态。 |
| B-04 | 业务已处理但消息确认失败，或处理超过锁续期预算 | **非原生** | 需消费者时序控制，核对重投、死信及重复业务操作；普通禁收不能替代。 |
| B-05 | 跨区域数据复制切换，验证消息保留和恢复 | **非原生** | 使用 Service Bus 自身 Geo-Replication；只复制元数据的 Geo-DR 不等价。 |

<a id="service-eventhubs"></a>
### 9. Event Hubs：6 项

官方依据：[消息动作目录][cs-messaging]列出事件中心状态变更；[元数据灾备][eh-dr]明确不复制事件，[数据异地复制][eh-geo]则复制事件及相关状态。

| 编号 | 测试场景 | Chaos Studio | 当前限制或其他实现方式 |
| --- | --- | --- | --- |
| H-01 | 禁止发送事件，验证生产者重试和缓冲 | **支持** | 已执行单事件中心状态变更；发布确认及事件完整性尚未验证。 |
| H-02 | 禁用事件中心，验证读写恢复 | **支持** | 已执行状态变更并恢复；消费检查点及重放尚未验证。 |
| H-03 | 业务处理后、保存消费检查点前中断消费者 | **部分支持** | 可用 Pod 删除制造消费者中断，但精确时点、事件重放及去重需应用配合。 |
| H-04 | 暂停消费者，制造积压后恢复追赶 | **非原生** | 需暂停专用消费者；禁用事件中心不等于只暂停消费，需控制积压及事件保留时间。 |
| H-05 | 跨区域元数据灾备切换 | **非原生** | 使用 Event Hubs Geo-DR；不复制事件数据，旧事件去向需单独说明。 |
| H-06 | 跨区域事件数据复制切换 | **非原生** | 使用 Event Hubs Geo-Replication，核对规格、复制状态和允许数据损失；不能用 H-05 替代。 |

<a id="service-routing"></a>
### 10. 负载均衡与应用网关：6 项

以下均为后续设计，目前没有获批测试目标；不因此操作 AKS 托管的共享负载均衡资源。

官方依据：[网络动作目录][cs-network]列出网络安全组规则及 Load Balancer 后端管理状态；未列出 Application Gateway 专属故障或精确探针异常动作。

| 编号 | 测试场景 | Chaos Studio | 当前限制或其他实现方式 |
| --- | --- | --- | --- |
| L-01 | Load Balancer 单后端不可用，验证摘流 | **支持** | 官方支持调整后端管理状态；只能证明后端被摘流，不能等同虚拟机实际宕机。 |
| L-02 | Load Balancer 单后端网络中断 | **待核验** | 有网络安全组规则动作，但目标关联、隔离及恢复方案待确认；管理状态变更不能替代。 |
| L-03 | Load Balancer 单后端健康探针异常 | **非原生** | 需专用探针响应或应用模拟，不能只把后端管理状态改为不可用。 |
| G-01 | Application Gateway 单后端实例或进程故障 | **部分支持** | 可在合格后端使用 VM 重启或 Pod 删除；不是应用网关专属动作，路由及业务验证需补充。 |
| G-02 | Application Gateway 单后端网络中断 | **待核验** | 可评估网络安全组规则基础能力，但精确目标和不影响共享网络的方案尚未确认。 |
| G-03 | Application Gateway 单后端健康探针异常 | **非原生** | 需专用探针响应或应用模拟，验证摘流及恢复纳流。 |

### 11. 所有依赖共用的客户端测试：5 项

以下按 MySQL、PostgreSQL、两种 Redis、Blob、Service Bus、Event Hubs 的实际协议分别执行。一个产品通过不代表其他产品通过。

官方依据：[网络动作目录][cs-network]和[官方场景模板][cs-scenarios]。例如 DNS 模板通过网络安全组阻断 53 端口实现，不等于只让一个指定域名解析失败。

| 编号 | 测试场景 | Chaos Studio | 当前限制或其他实现方式 |
| --- | --- | --- | --- |
| C-01 | 一个测试客户端到一个依赖的连接中断 | **待核验** | 有网络安全组阻断能力，但当前要求同时覆盖新旧连接、仅影响指定客户端和依赖，等价实现未确认。 |
| C-02 | 一个依赖访问路径增加延迟 | **非原生** | 需精确路径模拟；AKS 扩展的 Pod 整体网络延迟不等价。 |
| C-03 | 请求已到服务，但调用方未收到处理结果 | **非原生** | 需协议或应用配合制造“结果未知”窗口，验证不丢数据、不重复执行业务。 |
| C-04 | 指定依赖域名解析失败 | **待核验** | 官方有 DNS 阻断相关模板及网络规则动作，但单客户端、单域名的精确范围尚未确认。 |
| C-05 | 协议限流、连接或资源限制 | **非原生** | 需匹配实际驱动及协议的错误模拟；SQL、Redis、AMQP 不能统一当成 HTTP 限流处理。 |

<a id="service-cosmos"></a>
### 12. Cosmos DB：2 项，本轮不选

官方依据：[数据库动作目录][cs-databases]列出指定区域离线，不包含应用层未知结果或限流模拟。

| 编号 | 测试场景 | Chaos Studio | 当前限制或其他实现方式 |
| --- | --- | --- | --- |
| D-01 | 客户端连接异常、限流或结果未知 | **非原生** | 需客户端模拟，复用通用场景；不通过降低共享吞吐制造故障。 |
| D-02 | 指定区域离线，验证多区域读写和恢复 | **支持** | 官方有区域离线动作；需合格多区域账户，单区域账户不能执行。 |

<a id="service-rocketmq"></a>
### 13. RocketMQ：2 项，本轮不选

官方依据：[计算类动作目录][cs-compute]支持的是承载 VM 的故障；[完整动作目录][cs-catalog]未列出 RocketMQ 专用动作。

| 编号 | 测试场景 | Chaos Studio | 当前限制或其他实现方式 |
| --- | --- | --- | --- |
| V-01 | Broker 所在虚拟机重启，验证消息持久性和恢复 | **部分支持** | VM 重启可由 Chaos Studio 完成；Broker、消息确认、重投及业务完整性需额外验证。 |
| V-02 | Broker 所在虚拟机 CPU 或内存压力 | **部分支持** | 压力注入已有原生能力；消息积压、重试和持久性不是原生动作自动判定的结果。 |

### 14. 跨服务业务链路：3 项，后续验证

官方依据：[消息动作目录][cs-messaging]、[AKS 扩展][aks-extension]提供底层故障能力；[AKS 官方测试指导][aks-nodes]要求另外测量请求和已接收数据，而非只看故障动作结果。业务编排和验收是本项目设计。

| 编号 | 测试场景 | Chaos Studio | 当前限制或其他实现方式 |
| --- | --- | --- | --- |
| E-01 | 缓存故障时，业务回源数据库并恢复缓存 | **部分支持** | 可选原生缓存故障动作；业务回源、后端容量及数据正确性需实际应用验证。 |
| E-02 | 消息发送故障时，订单先入库及发件箱，恢复后补发 | **部分支持** | 可使用 B-01 禁发动作；发件箱、最终一致性和业务去重由应用实现并验证。 |
| E-03 | 消费者 Pod 中断后重投或重放，业务不重复执行 | **部分支持** | 可使用 K-01 删除 Pod；消息确认、检查点与唯一业务结果需应用配合验证。 |

## 三、几个容易混淆的边界

- **网络中断不是一律不支持。** Chaos Studio 有网络安全组规则及 DNS 中断相关模板；但本设计要求精确到测试客户端、依赖或域名，不能直接使用影响共享网络的方案代替。
- **Pod 故障不等于节点故障，单节点故障不等于整个可用区故障。**
- **固定内存压力不等于持续增长的内存泄漏。**
- **服务状态禁用不等于真实网络故障，也不等于消费者在指定时点崩溃。**
- **故障注入可由 Chaos Studio 完成，不代表业务验收也由它完成。** 数据完整性、重试、恢复时间和消息去重仍需独立验证。
- **当前清单不自动扩展到旧版模型或其他产品。** 不把旧版 Redis、Managed Redis、Service Bus、Event Hubs 的动作和复制语义混用。

<a id="05-原生能力优先本轮执行与暂缓标注"></a>
## 四、Workspace 配置复核与实际完成情况

<a id="workspace-configuration-audit"></a>

**结论：70 项中，12 项已建立独立 Scenario 和 `approved-targets` 配置，共绑定 7 个不同的 Azure 资源；58 项未建立独立配置。** 这是现有非生产 Workspace 的实时 ARM 核对结果，不是本次重新运行故障的结果。Workspace 里的 target 是 Configuration 中的资源筛选，不需要 classic Target/Capability，也不需要另建一套 Portal 配置。另有 25 个推荐场景未绑定 Configuration，不计为已建立。

### 4.1 已建立：12 项

以下各项已核对云端 `approved-targets` 的单 Action、参数、目标 ID、筛选与排除，均与原 Terraform 私有输入一致。Portal 进入现有 Workspace → **Scenarios** 后，选择下表 Scenario 和原 `approved-targets`。

| 编号 | Scenario | 实际绑定目标（脱敏） | 执行状态 |
| --- | --- | --- | --- |
| M-01 | `m01-mysql-ha-failover` | 同一台 MySQL Flexible Server | 历史已执行 |
| M-02 | `m02-mysql-restart` | 同一台 MySQL Flexible Server | 历史已执行 |
| P-01 | `p01-postgresql-planned-failover` | 同一台 PostgreSQL Flexible Server | 历史已执行 |
| P-02 | `p02-postgresql-forced-failover` | 同一台 PostgreSQL Flexible Server | 未执行；强制切换与数据恢复需另行授权 |
| R-01 | `r01-legacy-redis-primary-reboot` | 同一个旧版 Azure Cache for Redis，主节点 | 历史已执行；节点实际影响证据不足 |
| R-02 | `r02-legacy-redis-secondary-reboot` | 同一个旧版 Azure Cache for Redis，副本 | 历史已执行；节点实际影响证据不足 |
| B-01 | `b01-servicebus-send-disabled` | 同一个 Service Bus namespace 内的单一既有队列 | 历史已执行 |
| B-02 | `b02-servicebus-receive-disabled` | 同一个 Service Bus namespace 内的单一既有队列 | 历史已执行 |
| H-01 | `h01-eventhub-send-disabled` | 同一个 Event Hubs namespace 内的单一既有事件中心 | 历史已执行 |
| H-02 | `h02-eventhub-disabled` | 同一个 Event Hubs namespace 内的单一既有事件中心 | 历史已执行 |
| V-09 | `v09-private-vm-restart` | 单台既有测试 VM，不含恢复用 VM | 未执行；需核对 Broker、间接消费者及 guest 恢复 |
| N-07 | `n07-single-user-node-shutdown` | 单一 User VMSS + 指定 zone，排除 System VMSS | 未执行；ARM 复核指定 zone 匹配 1 个实例（该用户池共 2 个），仍缺私网 workload、容量与恢复证据 |

### 4.2 有原生动作但未建立：16 项

| 编号 | 未建立原因 | 建立前须满足 |
| --- | --- | --- |
| V-03、V-04 | 区域有 VM CPU／内存动作；候选测试 VM 当前没有托管身份，代理出站、资源余量和 Broker 间接影响未核实。 | 在原资源管理流程补齐获批身份和最小权限，核验代理兼容、出站、容量、低强度参数及恢复方案。 |
| K-01–K-05 | 现有 AKS 为 private，历史上扩展已安装，但 Workspace 当前没有 Pod Scenario 或 Configuration；没有经私网认证核实的获批 workload、namespace 和标签组合。微软将 private cluster 列为未验证配置，而非明确不支持。 | 从已批准的私网操作端核验扩展和工作负载；以确切 namespace 与标签交集限定 Pod。K-02/03 另核容器工具；K-04/05 另核 Linux amd64 网络组件与残留恢复，不开放公网 API。 |
| N-01 | 区域有 VMSS shutdown；现有 N-07 仅为单实例用途。复核中 User pool 的两个实例分属不同 zone，现有配置不能作为另一个多节点／zone 影响场景的证明。 | 明确批准的 User VMSS、zone 与实际实例清单、剩余容量和恢复，不沿用单节点授权或纳入 System 池。 |
| N-02、N-03 | 区域有 VMSS 压力动作；尚无证据证明当前方案只影响一个指定实例，而非整个规模集。仓库现有压力配置仅支持单独 VM，不支持 VMSS 实例级筛选。 | 先验证原生实例级选取方式和代理资格、容量及恢复，再配置；不得以整池压力替代。 |
| A-02 | Managed Redis 有一个现有数据库，但未确认数据独占且可完全重建，也未取得不可撤销清库授权。 | 选定隔离可重建数据库，核对清库影响、恢复证据和专项授权。 |
| A-04 | Managed Redis 当前无异地关联数据库可解除。 | 如纳入范围，需单独批准的异地测试拓扑、关联目标和重建恢复方案。 |
| S-03 | 现有 Storage 是 `Standard_ZRS`，无辅助区域，不能做计划性区域切换。 | 使用获批准且满足计划性切换条件的异地冗余测试账户；不为测试直接修改当前账户。 |
| B-03 | 区域有主题／订阅状态动作，但当前被绑定的 Service Bus namespace 中主题数为 **0**，没有可绑定的测试订阅。动作不会自动恢复原状态。 | 先明确专用测试 topic/subscription，并为两个变体分别确认目标权限、原状态和恢复步骤；不可复用队列动作。 |
| L-01 | 区域有后端管理状态动作，但在当前 scope 中只查到 AKS 节点资源组的 Load Balancer，没有获批的独立测试 LB/后端。 | 选定独立测试 LB、后端池和地址；不操作 AKS 托管共享 LB。 |
| D-02 | 当前 Cosmos DB 账户只有 **1 个区域**，且原测试范围未选此场景。 | 如纳入范围，需获批多区域测试账户、明确目标区域及读写恢复检查。 |

### 4.3 不能按原场景直接建立原生配置：42 项

| 类别 | 编号 | 缺口或替代方式 |
| --- | --- | --- |
| 非原生：主机／Pod | V-05、V-06、V-07、V-08、V-10、K-06、N-04、N-05 | 缺精确路径、卷、进程或渐进泄漏动作；须在隔离测试环境用主机／应用工具，Pod 整体故障不等价。 |
| 非原生：数据恢复／异地 | M-03、P-03、S-02、S-04、B-05、H-05、H-06 | 用服务自身 PITR、软删除／版本和复制／切换能力。S-02 还缺可读辅助区域；只复制元数据不等于复制数据。 |
| 非原生：缓存、客户端和时序 | R-03、R-04、A-03、S-01、B-04、H-04、C-02、C-03、C-05、D-01 | 需专用测试客户端及协议／应用控制；旧 Redis 全库清空须用获批隔离数据面的专项测试，不能借用 Managed Redis Action。 |
| 非原生：路由探针 | L-03、G-03 | 需专用后端和可控探针异常；管理面摘流不等于探针异常。 |
| 待核验：网络隔离或缺目标 | N-06、I-01、M-04、A-01、L-02、G-02、C-01、C-04 | 尚无满足单节点、单客户端、单依赖／域名或网格控制面边界的等价动作与恢复证据。MySQL 当前无独立只读副本；HA standby 不是只读副本。没有获批独立 LB／Gateway 后端或网格目标时不绑定共享资源。 |
| 部分支持：依赖未建立 | H-03、G-01、V-02、E-03 | 部分底层故障能力存在，但缺已核实的消费者 Pod、获批 Gateway 后端或符合资格的 Broker 压力目标；还需应用／路由层时序和恢复验收。 |
| 部分支持：可复用现有动作但未建立完整用例 | V-01、E-01、E-02 | V-01 可复用 V-09；E-01 可评估使用已绑定旧 Redis 重启动作；E-02 可复用 B-01。分别还需 Broker 持久性、缓存回源或发件箱／唯一业务效果验证，不能算独立 Scenario 已建立。 |

### 4.4 既有运行记录

以下运行历史已通过 ARM 核对；管理面影响及业务验收依据[原生测试报告](./chaos-studio-native-test-report.md)，本次未重跑：

| 项目 | 实际情况 |
| --- | --- |
| 已执行的不同场景 | 9 项：M-01、M-02、P-01、R-01、R-02、B-01、B-02、H-01、H-02。 |
| 原生运行 | 上述 9 项各执行两轮，共 18 次，原生运行和动作均成功。 |
| 管理面影响及恢复 | 7 项有通过证据；R-01、R-02 缺独立影响和恢复证据，结论仍不确定。 |
| 尚未执行 | 其余 61 项未执行；包括尚待配置、目标不满足、未获授权、本轮不选及未来范围。 |
| 尚未证明 | 完整技术验收、真实业务可用性、事务和消息完整性、端到端恢复时间，不能从原生运行成功直接推定通过。 |

**执行原则：** 仅在明确授权的非生产目标上测试，每次一个故障；先确认范围、备份、停止条件和恢复方法。清库、强制切换、区域切换、拓扑变更另行确认风险。取消运行不等于业务恢复，本清单不构成部署或故障执行授权。

执行步骤见[部署与测试操作手册](./terraform-deployment-runbook.md#chaos-test-operations)，真实结果见[原生测试报告](./chaos-studio-native-test-report.md)，工程任务见[实施计划](./chaos-studio-implementation-plan.md)。

## 五、能力依据

以上链接均为微软官方文档，本次已查阅。判断方式是：**动作目录确认原生能力，扩展文档确认 Pod 能力，服务文档确认备份及异地恢复能力；项目记录说明当前是否具备条件、是否已经执行。**

本次通过 ARM 读取了现有 Workspace、Scenario、Configuration、运行历史、UK South 区域动作目录和指定 scope 的相关目标元数据；未执行新的原生 Validate 或故障，未改动 Azure 资源、RBAC 或 Terraform state，也未重新验证 AKS 私网内 workload、应用数据面和恢复资格。官方有能力不代表当前目标必然适用；官方目录未列出也不写成所有产品版本永久不支持。

[cs-catalog]: https://learn.microsoft.com/en-us/azure/chaos-studio/chaos-studio-workspaces-supported-resources
[cs-compute]: https://learn.microsoft.com/en-us/azure/chaos-studio/chaos-studio-workspaces-supported-resources#compute
[cs-databases]: https://learn.microsoft.com/en-us/azure/chaos-studio/chaos-studio-workspaces-supported-resources#databases
[cs-cache]: https://learn.microsoft.com/en-us/azure/chaos-studio/chaos-studio-workspaces-supported-resources#caching
[cs-messaging]: https://learn.microsoft.com/en-us/azure/chaos-studio/chaos-studio-workspaces-supported-resources#messaging
[cs-network]: https://learn.microsoft.com/en-us/azure/chaos-studio/chaos-studio-workspaces-supported-resources#networking
[cs-storage]: https://learn.microsoft.com/en-us/azure/chaos-studio/chaos-studio-workspaces-supported-resources#storage
[cs-scenarios]: https://learn.microsoft.com/en-us/azure/chaos-studio/chaos-studio-scenarios
[aks-extension]: https://learn.microsoft.com/en-us/azure/chaos-studio/chaos-studio-aks-extension-overview
[aks-nodes]: https://learn.microsoft.com/en-us/azure/chaos-studio/chaos-studio-aks-guidance
[mysql-backup]: https://learn.microsoft.com/en-us/azure/mysql/flexible-server/concepts-backup-restore
[pg-ha]: https://learn.microsoft.com/en-us/azure/postgresql/high-availability/concepts-high-availability
[pg-backup]: https://learn.microsoft.com/en-us/azure/postgresql/backup-restore/concepts-backup-restore
[redis-admin]: https://learn.microsoft.com/en-us/azure/azure-cache-for-redis/cache-administration
[redis-geo]: https://learn.microsoft.com/en-us/azure/redis/how-to-active-geo-replication
[storage-planned]: https://learn.microsoft.com/en-us/azure/storage/common/storage-failover-customer-managed-planned
[blob-restore]: https://learn.microsoft.com/en-us/azure/storage/blobs/soft-delete-blob-overview
[sb-geo]: https://learn.microsoft.com/en-us/azure/service-bus-messaging/service-bus-geo-replication
[eh-dr]: https://learn.microsoft.com/en-us/azure/event-hubs/event-hubs-geo-dr
[eh-geo]: https://learn.microsoft.com/en-us/azure/event-hubs/geo-replication
