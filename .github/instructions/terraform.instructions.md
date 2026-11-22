---
applyTo: "**/*.tf,**/*.tfvars,**/*.tftest.hcl"

# Terraform 最佳实践与 Azure Chaos Studio 实施规范

适用范围：本仓库的 Terraform 根模块、`modules/`、`environments/*.tfvars`，以及后续 Azure Chaos Studio 配置。面向开发人员、评审人员及 AI 编程助手。

“必须”是安全与正确性要求；“建议”可以根据项目规模调整，但偏离时应说明原因。本文规定后续实施方式，不表示仓库现有配置已经符合全部要求。

> 加载说明：根目录 `instruction.md` 是人工阅读或显式附加的规范，GitHub Copilot 不会仅凭此文件名自动加载。若需要自动应用，可另行配置 `.github/instructions/terraform.instructions.md`，使用 `applyTo: "**/*.tf,**/*.tfvars,**/*.tftest.hcl"`，并在其中要求读取本文。

## 1. 工作边界

- 先阅读相关根模块、子模块、Provider 约束及 lockfile，再进行最小范围修改；保留现有公共输入输出及无关代码风格。
- 在用户原始仓库工作；未经明确同意，不创建 linked Git worktree。
- 创建代码或文档不等于授权部署。未经明确请求，不执行 `apply`、`destroy`、实验启动、资源重启、扩缩容或故障注入。
- 已授权实验范围内，可一起准备常规前置依赖，不需逐项重复询问；涉及扩大目标范围、破坏性动作或共享基础设施生命周期变更时，必须取得明确授权。
- 必须区分 **Terraform 资源配置** 与 **故障运行**。禁止通过 provisioner、REST action、定时器或部署流水线默认启动 Scenario / experiment。
- 不将客户正式验收或签署变成普通开发的额外阻塞；但实验执行前必须明确授权目标、影响、停止条件与恢复方案。

## 2. 目录与模块职责

- 保留根模块编排、`modules/<component>/` 封装资源、`environments/` 存放非敏感环境参数的结构。
- 新增 Chaos Studio 功能建议放在 `modules/chaos/`，提供 `main.tf`、`variables.tf`、`outputs.tf` 及模块说明；按复杂度拆分 `identity.tf`、`rbac.tf`、`scenarios.tf` 等，不为单个资源过度分层。
- 根目录沿用 `version.tf` 管理 Terraform / Provider 版本；`providers.tf` 放 Provider 配置。后续可将 backend 独立到 `backend.tf`，但不为命名一致而重排无关文件。
- 根模块配置 Provider；子模块声明 `required_providers`，需要别名时声明 `configuration_aliases`，由根模块显式传入，避免在可复用子模块内配置登录方式。
- Chaos 模块接收明确的目标资源 ID、作用域、身份配置和实验参数，不创建或接管共享 AKS、数据库、VNet 的生命周期。
- 已有资源通过输入、模块输出或 `data` 引用。同一 Azure 资源只由一个 state / resource address 管理；不得混用 AzureRM 与 AzAPI 重复管理。
- 优先使用 Provider-specific data source 或显式输出传递必要信息，避免为读取一个输出而开放完整远程 state。

## 3. HCL 风格、输入与依赖

- 使用两空格缩进、`snake_case` 的 Terraform 标识符、`#` 注释；用 `terraform fmt` 格式化被修改的文件。
- 每个变量必须有明确 `type` 和 `description`；可选参数提供安全默认值。每个 output 必须有 `description`，仅暴露使用方需要的值。
- 使用 `validation` 校验环境枚举、资源 ID 格式、非空目标、允许的命名空间、故障强度及持续时间；跨资源约束可使用当前 Terraform 版本支持的 precondition。
- 不提供生产目标、订阅范围授权、全命名空间匹配或全实例故障作为默认值。创建 Chaos 配置的可选开关建议默认关闭；它不是运行授权开关。
- 使用 `locals` 集中命名及公共 tags，避免重复拼接和过度抽象。建议 tags 包含 `environment`、`project`、`owner`、`cost_center`、`managed_by`；公开示例使用占位值。
- 多目标集合优先使用稳定 key 的 map 与 `for_each`，避免列表顺序变化导致 `count` 索引漂移；简单可选资源可使用 `count`。
- 优先通过资源属性引用建立隐式依赖。`depends_on` 只用于无法表达的真实依赖，不按文件顺序决定创建顺序，不添加无意义的模块级全量依赖。
- 避免 `null_resource`、`local-exec`、`remote-exec` 和固定 sleep。优先使用声明式资源及 Provider 的超时 / 重试；必要例外应说明幂等性、凭据处理、失败恢复和清理方式。
- Provider 初始化需要访问已存在的 AKS 时，建议分离 Azure 基础设施与集群内配置的部署阶段 / state，避免首次部署、销毁时的循环依赖。

## 4. 版本与供应链

- 固定执行环境中的 Terraform CLI 版本；`required_version` 应覆盖实际使用的语法与功能，不能保留不准确的最低版本。
- 新能力优先评估当前受支持的 AzureRM 稳定版本；已有 `3.115.0` 的升级必须作为独立变更评估迁移指南、schema、plan 和替换风险，不直接改成 `latest`。
- 根模块给 Provider 设置明确版本或受控范围，禁止无约束升级；提交 `.terraform.lock.hcl`，CI 使用 `terraform init -lockfile=readonly`，仅在专门升级变更中更新 lockfile。
- lockfile 锁定的是 Provider，不锁定远程模块。Registry 模块使用明确 `version`，Git 模块固定 commit；本地模块随仓库版本管理，不设置 Registry 专用的 `version` 参数。
- Helm chart、扩展及工具镜像固定已验证版本；支持时使用镜像 digest。评估第三方 Provider 的维护状态与必要性，不把 Registry 收录等同于 HashiCorp 官方维护。
- AzureRM 不支持所需资源时，才评估 `Azure/azapi`；固定 Provider 及已验证 ARM API version，遵循对应版本的 body / schema，使用 `jsonencode` 生成需要的 JSON，禁止猜测资源类型、字段或 action ID。
- 只从官方上游、官方发布仓库或发行版签名源安装工具；安装前说明风险，校验 SHA256 / 签名，使用 HTTPS、最小权限，禁止盲目 `curl | bash`。

## 5. State 与环境隔离

- 团队及云端部署使用 Azure Storage `azurerm` remote backend，启用 Microsoft Entra ID 认证、Blob lease 锁、传输加密、静态加密、受限网络访问及最小数据面权限。
- backend 存储应独立引导，不能由使用该 backend 的同一 state 创建后再自行依赖；保护 storage account / container，避免随实验环境一起销毁。
- 使用独立环境 root / backend key，并按安全边界隔离身份、权限及必要的 storage account / container。仅切换 `-var-file` **不会切换 state**。
- Terraform CLI workspace 名称不是权限隔离边界。必须记录并核对环境、backend、state key、Azure 身份和目标订阅的映射，禁止多个环境复用同一 state。
- 保留 state 备份、Blob versioning / soft delete，并验证恢复流程；备份和 plan 按敏感资产控制权限与保留期。
- backend 迁移必须先备份、停止并发写入并确认源 / 目标对应关系。禁止未经授权运行 `init -migrate-state`、`force-unlock`、`state rm` 或覆盖 state；更不能用空 state 掩盖问题。
- `.gitignore` 必须排除 `.terraform/`、state 及备份、lock info、保存的 plan、plan JSON、kubeconfig、`.env` 和含敏感信息的 tfvars。必须提交 `.terraform.lock.hcl` 与脱敏的配置样例。

## 6. 身份、机密与网络

- CI/CD 优先使用 OIDC / workload identity federation；Azure 执行环境优先 managed identity；人工操作可使用个人 Azure CLI 登录，但必须核对上下文，不让流水线依赖个人会话。
- 显式提供并核对目标订阅 / tenant 配置。不得在 `.tf`、已提交 tfvars、文档、日志或 shell history 中硬编码 client secret、密码、访问 key、证书或 kubeconfig。
- 敏感变量及 outputs 设置 `sensitive = true`；这只控制显示，不保证值不进入 state / plan。通过 Key Vault 读取的 secret 也可能进入 state；优先传递 secret 引用而非内容。
- 将 Terraform 部署身份、Chaos 运行身份、实验操作者、业务 workload identity 分离。创建 RBAC 的权限与执行故障的权限也应分开，禁止为方便默认授予订阅级 Owner / Contributor。
- 必须按所选 Action 所需权限和实际目标配置 RBAC；内置角色过宽时评估自定义角色。身份 object ID 与 client ID 不可混用。
- 保持 private AKS、数据库与 state 存储的安全边界；不得为 Terraform、Chaos 或测试方便开放公共访问、`0.0.0.0/0`、管理端口或禁用 TLS。
- 私有网络场景分别检查执行端、集群与 Chaos 服务所需的 DNS、出站访问及认证，不将一种资源模型的网络配置套到另一模型。
- 文档及公开证据必须脱敏真实资源名、registry / repository 名、cluster context、私网地址、subscription / tenant ID、run / request ID、个人邮箱与凭据。

## 7. Azure Chaos Studio 专项要求

### 7.1 先确认资源模型及支持矩阵

- 截至 2026-11-20，Microsoft Learn 推荐新韧性测试采用 **Chaos Studio Workspaces / Scenarios**；Experiments (classic) 是被替代的旧模型，仅在所需能力未被当前模型覆盖时评估使用。
- 实施前核对目标区域、资源类型、SKU、Action schema、API version 与当前 Provider 支持情况。文档中出现资源不等于本仓库锁定的 Provider 已支持它。
- Workspaces 使用 Workspace identity、scope、Scenarios 及 Actions；classic 使用 experiment identity、targets、capabilities 和 fault URN。不得混用权限、ID、故障版本、参数大小写或持续时间语义。
- Workspaces 的 region 与目标 region 不必相同；classic target / capability 的地域约束按对应文档执行，不写通用的“必须全部同区域”规则。
- 不因仓库包含 Redis、MySQL、Cosmos DB、Event Hubs 模块就认定某故障可用；必须按实际 Azure resource type 与资源模型核对。例如 Azure Cache for Redis 的 reboot 不能直接套用到 Azure Managed Redis。
- 若 Provider / API 支持或区域可用性尚未确认，明确列为实施待验证项，不生成猜测的资源配置，也不自动回退到旧模型。

### 7.2 限制 blast radius

- 每个实验定义：假设、目标清单、影响上限、持续时间、基线、业务通过条件、停止阈值、恢复步骤及执行授权范围。
- 优先专用开发 / 测试环境、单服务、小范围、短时、低强度故障；默认排除生产、系统命名空间、关键基础设施和不在授权范围的依赖。
- Workspaces 自动发现的 scope 是动态边界，不等于授权清单；运行前检查实际发现目标、过滤 / 排除规则及 RBAC，避免新增资源被意外纳入。
- Pod 目标必须限定 namespace 与 label；节点目标必须限定明确 node pool / VMSS / zone 并核实实际匹配实例。禁止空筛选器或默认全资源匹配。
- 根据 Action 区分 Discrete、Continuous、Cancelable；按 schema 校验 duration。不能假设所有动作都可取消、自动回滚或接受同一持续时间格式。
- 停止运行不等于业务恢复；清库、删除 Pod、重启、强制 failover 等不可逆或可能丢数据动作必须单独说明风险，准备相应数据与业务恢复措施。
- 不同时执行作用域重叠的故障运行；实验期间不让 Terraform / GitOps / 自动化反复纠正临时故障状态。不要用宽泛 `ignore_changes` 永久掩盖 drift。

### 7.3 AKS：区分节点故障与 Pod 故障

- Workspaces 节点韧性测试针对 AKS infrastructure / node resource group 中的 VMSS，而不是仅针对 AKS cluster resource。通过 AKS 属性发现 node resource group，不硬编码 Azure 自动生成的名称。
- 对 AKS 管理的 VMSS 只做明确授权的测试，不将其导入普通 Terraform 管理并修改节点池生命周期；此方法不适用于 NAP 创建的节点池。
- 节点测试前确认区域 / zone 分布、真实副本放置、剩余容量、存储区域约束、调度策略及 autoscaler 行为；不默认认为节点关闭代表完整可用区故障。
- PDB 主要约束自愿驱逐，不能保证 Pod 删除、节点丢失或其他故障注入遵守同等保护，必须验证具体故障行为。
- Workspaces 的集群内 Pod 故障使用 **Chaos Studio extension for AKS（preview）**；classic Chaos Mesh 是不同路径，不能把安装 Chaos Mesh 作为所有 Chaos 测试的统一前提。
- 采用 AKS extension 前检查 Linux / 架构、已验证 Kubernetes 版本、OIDC issuer、Workload Identity、Azure RBAC、命名空间及网络要求。该 preview 不用于生产；private cluster 等未验证配置不能写成已受支持。
- classic Chaos Mesh 路径检查兼容版本、Linux node pool、container runtime、CRD readiness、私网连接与专用权限；仅启用使用到的 target / capabilities。
- Chaos 控制组件可能需要特权权限或节点 runtime socket。说明其安全风险并限制在专用组件；业务验证 Job 不挂载本机目录或本机 Docker socket，不将集群级安全策略整体放宽。
- 网络故障可能在运行结束后残留，即使报告显示 `Succeeded`；必须验证实际连通性，并在授权恢复范围内处理受影响 Pod / workload。

## 8. 变更、计划与部署流程

1. **准备**：核对 Terraform / Provider 版本、认证上下文、环境参数、backend、已有资源 ownership、变更范围及实验是否正在运行。
2. **静态检查**：先执行 `terraform fmt -check -recursive`；初始化 Provider 后执行 `terraform validate`。纯配置校验可使用 `init -backend=false -lockfile=readonly`，但这不是部署就绪或云端验收证明。
3. **安全检查**：使用固定版本的 TFLint 及一种适用的 IaC 扫描 / policy 工具；优先检查未授权目标、宽权限、公开访问、敏感 outputs、缺失 tags 与自动运行故障。
4. **生成 plan**：明确环境参数及正确 backend，使用 `terraform plan -out=<private-plan-path>` 保存计划；`-detailed-exitcode` 的 `0` 表示无变更，`2` 表示有变更，`1` 表示错误。
5. **审查 plan**：必须检查 create / update / delete / replace、RBAC scope、目标筛选、网络变更、成本及共享资源影响。真实 plan / JSON 不发布到公开 PR 评论或文档。
6. **应用**：仅在用户或受控流水线已明确授权后，应用审查过的同一 saved plan；代码、state、变量或权限发生实质变化时重新生成和审查。禁止默认 `-auto-approve`，禁止靠 `-target` 作为正常部署方式。
7. **部署验证**：检查 provisioning state、配置、RBAC 生效与 drift；`depends_on` 只保证顺序，不保证 RBAC 已传播。新实验资源创建成功后，仍不得自动启动实验。
8. **运行与恢复**：另行执行已授权的故障测试；恢复完成后重新 plan，调查非预期 drift。不以 `terraform destroy` 代替实验停止或业务恢复。

- 流水线按 environment / state 设置并发互斥，同时保留 backend 锁；日志和 artifacts 设置权限与保留期。
- 资源改名 / 模块迁移优先使用当前版本支持的 `moved` / `import` 工作流，先审查 plan；禁止通过删 state 再创建来规避迁移。
- 对重要持久化资源评估 `prevent_destroy`、Azure locks、备份；说明它们的局限及与测试操作的冲突，不能视为绝对防删除保证。
- 清理仅限当前变更拥有的临时资源、role assignments、targets / capabilities 或扩展；不得删除共享目标及 remote backend。

## 9. 测试与结果判定

- **静态检查不是云端测试。** 本机只作为编辑、构建和操作端；业务与韧性验证在云端 AKS 执行，不以本地结果替代。
- 业务验证脚本优先使用 ConfigMap + 固定工具镜像 + AKS Job；设置 resource requests / limits、超时、有限重试及清理策略，不为每次脚本更新强制重建镜像。
- Terraform module tests 优先覆盖输入约束、目标过滤、最小权限、功能开关和资源 ownership。区分 mocked / plan-only 检查与真实 apply tests；后者可能创建并销毁资源，必须受授权与独立环境约束。
- 实验前采集正常流量基线；期间和结束后检查请求成功率、延迟、节点 / Pod readiness、重试 / 超时、恢复时间和已确认数据的完整性。
- 将 Chaos 报告与 Kubernetes events、业务指标和数据检查结合。`Succeeded` 只说明动作记录成功；`Skipped` 或未命中真实流量的故障不能判为通过。
- 结果使用 `Passed`、`Failed`、`Inconclusive`、`Blocked` 并用中文解释依据、缺失证据或阻塞原因；不得把未执行验证写成已通过。
- 测试覆盖率是非阻塞评审信号，不设全局硬性百分比；重点覆盖误伤目标、权限扩大、无法恢复及数据丢失等实际风险。


## 10. 交付检查清单

- 变更范围最小，未引入未授权云操作或自动故障启动。
- Terraform / Provider / module / chart / image 版本可复现，lockfile 正确。
- 环境、backend、身份、资源 ownership 与目标清单已核对。
- Inputs 有类型及必要校验；outputs / state / plan / 文档不泄露机密。
- Chaos 资源模型、API / Provider 支持、区域及实际资源类型匹配。
- RBAC 与目标过滤限制 blast radius，shared / production 资源默认不受影响。
- 已报告静态检查、plan 审查和云端验证各自结果；未执行项明确标注。
- 已准备停止及恢复措施，确认真实业务恢复后再结束实验。

## 11. 官方参考

查阅日期：2026-11-20。实施时重新核对当前版本及支持矩阵，避免把旧示例当成当前产品能力。

- [HashiCorp Terraform Style Guide](https://developer.hashicorp.com/terraform/language/style)
- [AzureRM Provider 文档（实施时选择锁定版本）](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs)
- [Azure Chaos Studio 概述](https://learn.microsoft.com/en-us/azure/chaos-studio/chaos-studio-overview)
- [Chaos Studio Workspaces 概述](https://learn.microsoft.com/en-us/azure/chaos-studio/chaos-studio-workspaces-overview)
- [Workspaces 支持的资源与 Actions](https://learn.microsoft.com/en-us/azure/chaos-studio/chaos-studio-workspaces-supported-resources)
- [Workspace 身份与权限](https://learn.microsoft.com/en-us/azure/chaos-studio/chaos-studio-workspace-permissions)
- [AKS 节点韧性测试](https://learn.microsoft.com/en-us/azure/chaos-studio/chaos-studio-aks-guidance)
- [Chaos Studio extension for AKS（preview）](https://learn.microsoft.com/en-us/azure/chaos-studio/chaos-studio-aks-extension-overview)
- [Experiments (classic) Fault Library](https://learn.microsoft.com/en-us/azure/chaos-studio/chaos-studio-fault-library)
- [Classic AKS Chaos Mesh 教程](https://learn.microsoft.com/en-us/azure/chaos-studio/chaos-studio-tutorial-aks-portal)