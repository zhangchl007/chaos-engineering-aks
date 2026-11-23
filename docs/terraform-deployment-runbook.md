# Terraform 部署与 Chaos 测试 Runbook

所有命令从仓库根目录执行。项目流程：**Platform → 按需配置 Cluster → Chaos Studio Workspace / Scenario → 单独授权故障运行**。Bootstrap 和远程 backend 可选；Chaos Studio 是项目主流程，不是被省略的附属步骤。全部 Chaos 操作步骤见[第 8 节](#chaos-test-operations)，用例定义与验收仍以[唯一清单](./chaos-test-and-coverage-plan.md)为准。

## 1. 准备

- 使用 Terraform 1.15.6 和仓库锁定的 Provider；保留各阶段 `.terraform.lock.hcl`，不使用 `-upgrade`。
- 确认 Azure 身份、订阅和目标环境。人工使用 Azure CLI 登录；CI 使用独立的 federated identity，不依赖个人会话。
- 保留已有 state，变更前私下备份，避免并发操作。切换 `.tfvars` 不会切换 state；已有 backend 迁移必须另行授权。
- state、私有输入、密码和计划均按敏感文件保护，不提交或公开。禁用组件可能删除已有资源，必须审查 plan。

```bash
umask 077
install -d -m 700 local-state/dev/private local-state/dev/chaos-testing
```

| 阶段 | 默认 state | 计划文件 |
| --- | --- | --- |
| Platform | `local-state/dev/platform.tfstate` | `local-state/dev/private/dev-platform.tfplan` |
| Cluster | `local-state/dev/cluster.tfstate` | `local-state/dev/private/dev-cluster.tfplan` |
| Chaos | `local-state/dev/chaos.tfstate` | `local-state/dev/private/dev-chaos.tfplan` |

三个阶段默认使用独立的本地 state，不需要 Storage account 或 backend 配置文件。

## 2. 初始化：只在需要时执行

**已初始化直接 plan/apply。** 首次使用或模块、Provider、backend 配置变化时，才初始化受影响的阶段。

首次安装 Provider：

```bash
# 只执行需要初始化的阶段
terraform init -input=false -lockfile=readonly
terraform -chdir=stacks/cluster init -input=false -lockfile=readonly
```

已有完整的锁定版本缓存时，用下面的命令替代联网初始化；不要两组都执行：

```bash
terraform init -input=false -lockfile=readonly \
  -plugin-dir="$PWD/.terraform/providers"
terraform -chdir=stacks/cluster init -input=false -lockfile=readonly \
  -plugin-dir="$PWD/stacks/cluster/.terraform/providers"
```

`-plugin-dir` 只使用指定目录，缺少版本时停止，不自动下载或升级。首次下载需要代理时，仅为该次命令设置已授权的 `HTTPS_PROXY` 和 `TF_REGISTRY_CLIENT_TIMEOUT=120`。

## 3. Platform：plan → 审查 → 授权 apply → replan

### 第一阶段交付范围

| 必需组件 | 计划要求 |
| --- | --- |
| AKS、VNet、subnets、监控 | 保留已部署资源及原 state，不因补齐组件而重建 |
| MySQL、PostgreSQL、Managed Redis、Event Hubs、Service Bus、Storage | 保留现有实例，核对私网连接和业务身份访问 |
| **新建 Azure Cache for Redis**（`Microsoft.Cache/redis`） | 与 Managed Redis 分开；Standard C1、独立 Private Endpoint/DNS/VNet link；禁用公网、明文及 key 认证，为专用 AKS workload identity 配置数据访问 |
| jumpserver / RocketMQ VM、NIC、NSG | jumpserver 启用公网 IP，RocketMQ 保持私有；保留 dev 原有 NSG 规则且暂不附加，不接管公司 NSG；公网 jumpserver 使用独立、实际附加的 SSH 访问 NSG |
| RocketMQ 运行组件 | 安装并验证 NameServer / Broker 和私网业务连接，VM 创建成功不等于 RocketMQ 已安装 |
| Cosmos DB | **可选，当前不创建业务资源**；保留已有 DNS/link/命名资源，不阻塞其它组件 |

Azure Cache 新建前确认租户资格：[Microsoft 最新创建规则](https://learn.microsoft.com/en-us/azure/azure-cache-for-redis/cache-whats-new#july-2026)允许 2026-04-01 前已有 Azure Cache 的租户继续创建 Basic/Standard/Premium；新客户在 Azure public cloud 仍受创建限制。不得未经确认设置 `eligibility_confirmed = true`，也不擅自用 Managed Redis 替代这一独立要求。

实施顺序：**保留已有平台/PaaS → 补齐 Azure Cache 新建接线 → 补齐私有 VM/NSG/运行组件 → 云端连通性与业务验证 → 相同输入 replan 检查幂等 → 进入 Chaos Studio 配置与故障测试**。第一阶段必须实际包含这些组件及其依赖，不能仅凭没有资源变更的 plan 宣告完成。

### 当前配置与部署操作

[dev 配置](../environments/dev-variables.tfvars) 启用六项已有 PaaS、独立 Azure Cache、带公网 IP 的 jumpserver 和私有 RocketMQ VM，并引用已有 ACR。Azure Cache 的租户资格开关只适用于已核实的当前 dev tenant；切换 tenant 必须重新确认。

原 NSG 定义及规则保留，`attach_nsg = false` 只关闭它们的 NIC 附加。jumpserver 另附加独立 SSH 访问 NSG，不复用通配规则；`jumpserver_ssh_source_cidrs` 仅接受批准的 /24 或更窄管理 CIDR，建议 /32。真实地址通过私有 tfvars/`TF_VAR_jumpserver_ssh_source_cidrs` 提供，不写入公开配置；未提供时默认拒绝全部入站，输出 `ssh_access_status = "Blocked"`。RocketMQ 不创建公网 IP。干净环境仍默认创建/附加原模板；附加前须收窄规则，不把公司策略或未附加的 NSG 当成已验证的访问控制。

两台 VM 使用已核对区域可用性的 Ubuntu 22.04 Gen2 固定镜像。RocketMQ VM 通过 cloud-init 安装 SHA512 校验的 Apache 5.5.1 二进制和发行版签名 JRE17，运行独立用户的 `rocketmq-nameserver` / `rocketmq-broker` systemd 服务；消息目录为 `/var/lib/rocketmq/store`。安装需 HTTPS 出站；不改变已有 subnet/NSG 的出站配置。VM provisioning 成功不代表 cloud-init 或业务验证通过。

当前 Cosmos 设置为 `components.cosmosdb = false`、`retain_cosmos_network = true`：保留已有 DNS zone、VNet link 和命名资源，不创建账户、数据库、容器、Private Endpoint 或数据角色。不要用 `-var='components={cosmosdb=false}'` 替换整个组件对象。

根模块的订阅/tenant 可从认证上下文获取；显式输入覆盖上下文。已由 state 管理的生成密码保持原输入模式，不要把打印的密码重新写回显式输入。

```bash
terraform fmt -check -recursive
terraform validate
terraform plan -input=false -detailed-exitcode \
  -var-file=environments/dev-variables.tfvars \
  -out="$PWD/local-state/dev/private/dev-platform.tfplan"
```

退出码 **0 = 无变更，2 = 有变更，1 = 错误**。错误时停止，不应用旧计划。本轮只允许新增：已部署平台、PaaS、原有 NSG 的 update/delete/replace 均为 0；出现其它动作先停止调查，不通过删 state 或 `-target` 绕过。

```bash
terraform show -no-color "$PWD/local-state/dev/private/dev-platform.tfplan"
```

只有明确授权后，应用审查过的同一计划：

```bash
terraform apply -input=false "$PWD/local-state/dev/private/dev-platform.tfplan"
```

应用后，用相同输入重新执行 plan，检查无非预期资源变化。代码、state、输入或权限实质变化时重新生成和审查计划；不用 `-target` 或默认 `-auto-approve`。

在私有终端读取 `terraform output -json vm_connections` 和 `terraform output -json azure_cache`。Cache 输出包含 SDK TLS 地址、client ID 及固定 namespace/service account；Cluster 中对应 ServiceAccount 注解该 client ID，验证 Pod 使用 `azure.workload.identity/use: "true"`。业务验证仍在云端 AKS 执行；未运行 Job、未核对 RocketMQ 服务和消息收发前，不宣告第一阶段通过。

需要密码时，在私有终端显式读取，勿录入公开日志：

```bash
terraform output -raw mysql_admin_password
terraform output -raw postgresql_admin_password
```

## 4. Cluster：准备输入并按需配置

**当前仅安装 Chaos Studio，不安装 Argo CD / ingress：跳过本节的 Cluster plan/apply，直接进入第 5 节。** 保持 `ingress_mode = "none"`、`enable_argocd = false`、验证 Jobs 关闭。创建 Workspace 或安装 AKS Chaos 扩展不依赖 ingress/Argo CD；后续需要业务验证 Jobs 时再单独授权 Cluster 配置及流量。

先确保平台的 `cluster_id`、`cluster_name`、`resource_group_name` 输出存在。下面为 Azure CLI 操作员生成四个必要输入，不读取密码、不覆盖已有配置；CI 使用自己的批准输入。

```bash
python3 - <<'PY'
import json
import os
import pathlib
import subprocess

path = pathlib.Path.cwd() / "local-state/dev/private/dev-cluster.private.tfvars"
path.parent.mkdir(mode=0o700, exist_ok=True)
if path.exists():
    print("保留已有 cluster 私有输入。")
else:
    def output(name):
        return json.loads(subprocess.check_output(
            ["terraform", "output", "-json", name], text=True))

    subscription = output("cluster_id").split("/")[2]
    tenant = subprocess.check_output([
        "az", "account", "show", "--subscription", subscription,
        "--query", "tenantId", "-o", "tsv"], text=True).strip()
    if not tenant:
        raise RuntimeError("无法确认平台订阅的 tenant；停止生成输入。")
    values = {
        "subscription_id": subscription,
        "tenant_id": tenant,
        "cluster_name": output("cluster_name"),
        "cluster_resource_group_name": output("resource_group_name"),
    }
    fd = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
    with os.fdopen(fd, "w") as stream:
        stream.write("".join(f"{key} = {json.dumps(value)}\n"
                             for key, value in values.items()))
    print("已生成权限 0600 的 cluster 私有输入；组件保持默认关闭。")
PY
```

Ingress、Argo CD、验证 Jobs 默认关闭。需要启用时，先按 [Cluster 说明](../stacks/cluster/README.md) 配置私有输入并确认 `kubelogin`、私有 API/DNS 连通性、Entra/Kubernetes 权限、TLS 和对应组件要求；根模块选项不会自动传入此阶段。

需要初始化时执行第 2 节，然后：

```bash
terraform -chdir=stacks/cluster validate
terraform -chdir=stacks/cluster plan -input=false -detailed-exitcode \
  -var-file="$PWD/local-state/dev/private/dev-cluster.private.tfvars" \
  -out="$PWD/local-state/dev/private/dev-cluster.tfplan"
```

退出码 1 时停止；成功后审查新计划：

```bash
terraform -chdir=stacks/cluster show -no-color "$PWD/local-state/dev/private/dev-cluster.tfplan"
```

仅在 plan 成功并明确授权后应用：

```bash
terraform -chdir=stacks/cluster apply -input=false "$PWD/local-state/dev/private/dev-cluster.tfplan"
```

随后用相同输入重新 plan。默认组件关闭时只有连接/空验证输出，不表示已安装 add-ons。启用验证 Jobs 会运行请求，必须另行授权测试流量。

## 5. Chaos Studio：创建 Workspace，再配置故障

Chaos Studio 是 Azure 托管服务，不是 Helm chart。此阶段创建 Workspace、专用运行身份和资源发现权限；填写 Scenario 后创建故障配置，**不会启动故障**。

1. 在 Azure Portal 核对 `Microsoft.Chaos` 已注册；未注册时由有权限的管理员明确授权注册。
2. 将 [Chaos 输入样例](../environments/dev-chaos.example.tfvars) 复制到私有目录，填写所有占位值，不覆盖已有配置：

   ```bash
   cp -n environments/dev-chaos.example.tfvars "$PWD/local-state/dev/private/dev-chaos.private.tfvars"
   ```

   初次仅创建 Workspace 时，保留 `scenarios = {}`、`permissions = {}`、`aks_extensions = {}`、`pod_scenarios = {}`。已有平台无需重新 init/plan/apply；沿用原有 state/backend。以下 Terraform 命令保持原流程的 `-chdir`、缓存 Provider、readonly lockfile 和 saved-plan 授权方式，不添加 `-upgrade`、`-target` 或 `-auto-approve`。

3. 明确 Workspace 区域和非生产 RG scope。支持区域为 `eastus2`、`westus2`、`westcentralus`、`northeurope`、`swedencentral`、`uksouth`、`japaneast`；Workspace 可跨区管理目标，[UAE North 不是 Workspace 部署区域](https://learn.microsoft.com/en-us/azure/chaos-studio/chaos-studio-region-availability)。区域和数据驻留需确认，不自动迁移目标。
4. 首次初始化只复用平台已有的两个锁定 Provider，然后校验和 plan：

   ```bash
   terraform -chdir=stacks/chaos init -input=false -lockfile=readonly \
     -plugin-dir="$PWD/.terraform/providers"
   terraform -chdir=stacks/chaos validate
   terraform -chdir=stacks/chaos plan -input=false -detailed-exitcode \
     -var-file="$PWD/local-state/dev/private/dev-chaos.private.tfvars" \
     -out="$PWD/local-state/dev/private/dev-chaos.tfplan"
   ```

   Provider 尚未安装时先走第 2 节的联网安装方式；已经初始化则省略 init。退出码 1 时停止。
5. 审查新计划：初始样例仅创建 Workspace、UAMI 和指定 RG 的 Reader 发现授权，不创建 Scenario 或运行故障。明确授权后才应用：

   ```bash
   terraform -chdir=stacks/chaos show -no-color "$PWD/local-state/dev/private/dev-chaos.tfplan"
   ```

   审查完成且明确授权后执行：

   ```bash
   terraform -chdir=stacks/chaos apply -input=false "$PWD/local-state/dev/private/dev-chaos.tfplan"
   terraform -chdir=stacks/chaos output -raw workspace_id
   ```

6. 在 Workspace 中核对发现资源。**Workspace/scopes/Reader 创建成功不证明已有资源发现快照。** 若列表为空，核对 scope 与 Reader 后，显式执行原生发现（不启动故障）：

   ```bash
   workspace_id="$(terraform -chdir=stacks/chaos output -raw workspace_id)"
   az rest --method post \
     --url "${workspace_id}/discover?api-version=2026-08-01-preview"
   az rest --method get \
     --url "${workspace_id}/discoveredResources?api-version=2026-08-01-preview"
   ```

   `discover` 是异步操作；按响应的 Location/Retry-After 等待，确认目标出现在发现结果，并处理 `nextLink`。完整输出含真实标识，只保留私有。Workspaces 资源发现不是 classic Targets/capabilities；不用部署 classic target/capability 补齐。
7. 按 [Chaos 模块说明](../modules/chaos/README.md) 填写明确目标、单 Action 参数、排除项及验证所得的最小权限，再次 plan、审查并授权 apply。Reader 发现权限不是执行故障权限；不要自动授予 Contributor。新角色可能尚未传播；对失败配置检查实际缺失权限并重验，不默认调用 `fixResourcePermissions`。必须原生 validation `Succeeded` 且实际解析到获授权目标，才交给用户显式 Execute。

### 2026-11-23 原生目标关联

已在原 Chaos state 新增 M-01/M-02/P-01/R-01/R-02/B-01/B-02/H-01/H-02/V-09 十个单 Action Scenarios，每个配置名为 `approved-targets`，精确绑定六个已有 PaaS/私有 VM 资源；queue/hub进一步限定已有明确实体。显式发现后资源数为57；这些发现资源不是全部授权故障目标。两批审查/apply 共10个 Scenarios、10个 Configurations、6个目标 custom roles 和6个 assignments，已有资源 update/delete/replace 为0。全部10项原生 validation `Succeeded`，实际解析到唯一指定目标；未执行故障。

后续 plan 必须使用保存的完整私有原生配置输入，不使用 `scenarios = {}` 的初始 onboarding 样例，否则可能删除已建场景/授权。不运行 Platform/Cluster apply、不修改 private AKS 网络，不创建自定义测试应用。最新各配置 validation/暂缓状态见[统一清单](./chaos-test-and-coverage-plan.md#05-原生能力优先本轮执行与暂缓标注)；当前未启动故障。

### 原生准备状态修正与补齐

当前进一步新增 P-02 forced HA failover 与 N-07 单 User-node shutdown，仍使用原 Chaos owning state。节点组从 AKS `nodeResourceGroup` 属性发现，只使用已有批准的节点组例外；追加该 scope 的 Reader 和明确 User VMSS 的 target-only custom role/assignment。System VMSS 在全部配置中排除，不导入 AKS 管理的节点资源，不修改节点池或 private API/DNS/网络。

实例级 ARM 证据确认 User pool 两个 Running 实例分别在 zone 2、3；N-07 单 VMSS/region/zone 2 当前匹配一个实例，1分钟、graceful shutdown。每次运行前重新核对恰好一个实例、workload/存储放置与剩余一节点容量，不能因 validation 返回一个 VMSS 就认定只影响一节点。P-02 模式为 `ForcedFailover`，运行/恢复风险单独确认；配置不等于授权。

审查并应用同一 saved plan：7 create、11 metadata update、0 delete/replace。更新仅 Workspace scope 与原十项配置的 System 排除，原 Actions/目标/参数/权限不变。刷新发现69个资源；当前12项单故障配置、7个明确目标资源，12/12原生 validation `Succeeded`。N-07 首次权限求值待 Reader 传播，核对实际 assignment/principal/scope 后有限重验通过；没有调用自动权限修复。相同完整输入 replan exit code 为0。未启动故障。

准备状态应区分待配置、待目标、待补前置、待核验、待授权与已证实阻塞。原生 VM pressure 在运行时自动安装 agent 并保留，不需手工预装；当前 VM identity 缺失、public outbound/headroom 待核验，因此不加入 pressure qualification allowlist、不默认改平台身份或开放网络。private AKS Pod extension 的未验证配置不是平台明确不支持；从既有私网操作端核验当前获授权 Pod，不把旧空 namespace 记录当永久阻塞。

### 本轮实际原生执行与报告

2026-11-23 在上述配置准备后实际执行 M-01/M-02/P-01/R-01/R-02/B-01/B-02/H-01/H-02 九项单故障，9个 run / Action 均 Succeeded；7项管理面状态影响与恢复有直接证据，Redis 两项节点影响证据不足为 Inconclusive。五个目标最终 Resource Health Available，数据库 Ready / HA Healthy、消息实体 Active，无活动运行，private AKS 未改变。Chaos 配置栈恢复后 replan 为0，不代表完整 Platform state 或业务验收。

MySQL 查询超时通过同一 run 恢复观察，没有重发 Execute；PostgreSQL 首次收尾 Resource Health Unavailable，核验 Available 后才继续。完整数据/业务验收、未运行场景与能力缺口见[原生测试报告](./chaos-studio-native-test-report.md)。前述配置/安装阶段“未启动故障”保留为历史，不覆盖本轮实际结果。

### AKS 故障组件安装

- **节点故障**：针对已核实的 node RG / VMSS / zone，走 service-direct Action，不需要给集群安装 Pod 故障扩展。不得接管 AKS 管理的 VMSS 生命周期。
- **Pod 故障**：由操作员另外[安装 Chaos Studio extension for AKS](https://learn.microsoft.com/en-us/azure/chaos-studio/chaos-studio-aks-extension-install)。安装前确定独立测试 namespace，并通过 `experiments.targetNamespaces` 显式传入；当前官方流程修改名单需要卸载重装。不要使用默认 namespace，也不要放宽现有 restricted 验证 namespace。扩展、subscriber identity/federation、内置 operator role assignment 和 Workspace connection 仍由安装流程拥有；Terraform 不重复创建。完成兼容性核对后，按 [模块说明](../modules/chaos/README.md) 配置引用式 Pod Scenarios，仍不会自动启动故障。
- 当前集群是 private AKS；[官方 preview 支持说明](https://learn.microsoft.com/en-us/azure/chaos-studio/chaos-studio-aks-extension-overview#validated-configurations)列明 private clusters 未验证。因此不自动安装、不声称 Pod 故障可用，也不开放公网或自动改走 classic Chaos Mesh。

### 2026-11-22 安装进度：仅安装，不运行故障

- 用户确认 Workspace 使用 **UK South**，现有 AKS / PaaS 保持 **UAE North**，并授权安装 AKS preview 扩展；不安装 Argo CD / ingress，不运行业务验证 Jobs 或任何故障。
- 已注册 `Microsoft.Chaos`；已使用原有 `-chdir`、Provider 缓存、readonly lockfile 和同一 reviewed saved plan 部署 Workspace、一个专用 UAMI 及现有 dev RG 的 Reader 发现授权。未修改平台、网络或节点池。
- **Passed：** Workspace provisioning 为 `Succeeded`，区域、单一身份及 Reader scope 已核对；Terraform 未创建 Scenario/configuration，相同输入 replan 的 detailed exit code 为 0。Workspace 会自动填充推荐 Scenario library，不应把 library 数量当作已配置/已运行的实验数量。
- 已在操作员私有工具目录安装官方 `k8s-extension` CLI **1.9.5**，安装前核对 Microsoft extension index SHA256；未升级全局 Azure CLI / Provider。区域 catalog 返回该集群可用的 `Microsoft.ChaosStudio` 版本 **0.1.12**，release train 为 `dev`。
- **初始阻塞：** 原操作端不能解析 private AKS API DNS；现有 jumpserver SSH 也为 Blocked，且没有已有可信 host key。后续通过已有私网 runner 的 VM 管理通道完成安装，未绕过主机认证、开放 SSH / API 公网、改 DNS 或放宽安全策略。
- **后续网络检查 Passed：** 用户选择现有私网 runner 后，通过已有 Azure VM Run Command 管理通道执行限时、无凭据的 DNS/HTTPS 检查。VM 和 AKS 的 Azure Resource Health 均为 `Available`；runner VM 为 running，agent 为 Ready，无失败/更新中的扩展。从 runner 可解析 private AKS API，并使用该集群 CA 完成 TLS/hostname 验证；API 返回 `401`，证明传输可达，不代表认证已通过。Azure Resource Manager、Entra ID、Microsoft Artifact Registry 和官方 CLI 扩展下载地址也完成 DNS/TLS 检查。
- SSH 不是所有私网管理方式的统一前提：已有 VM 管理通道可用于检查网络，无需增加 NSG、防火墙、NetworkPolicy 或 admission 限制，也无需开放公网 API/SSH。此次没有修改这些网络/安全配置。原操作端 DNS 问题仍存在，但不能据此认定 runner 到集群的网络不通。
- **安装完成 Passed：** runner 独立目录安装 Azure CLI **2.87.0**、`k8s-extension` **1.9.5**、kubectl **1.36.5** 和 kubelogin **0.2.18**；官方下载已核对 SHA256。通过独立 venv 引导 pip，未改全局 apt/Python 包。用户明确授权临时 managed identity 和安装权限；仅在 dev AKS 与 Workspace 授予自定义安装角色，role-assignment write 通过 ABAC 限定为 Workspace identity 与内置 Chaos operator role。未授予订阅级 Owner/Contributor 或 node RG 权限，未复制操作员 tokens/passwords/kubeconfig。
- **扩展就绪 Passed：** 官方安装流程完成 `Microsoft.ChaosStudio` **0.1.12**（`dev`），provisioning `Succeeded`，auto-upgrade 关闭，subscriber 与 network daemon 均启用。两个 Deployment 各 1/1 Ready，DaemonSet 4/4 Ready，共 6/6 control pods Ready。专用 `chaos-targets` namespace 已创建且没有 workload Pod。已核对 installer-owned subscriber UAMI/federation、Workspace connection 的 target/principal/tenant/endpoint 及 cluster-scoped 内置 operator role。
- **网络与测试边界：** runner 到实际 Workspace endpoint 的 TLS/hostname 验证通过；HEAD 返回 `404`，只作传输证据，不作已认证订阅/业务通过证据。subscriber 近期日志未发现所检查的传输错误，但也没有明确连接成功消息。connection 显示 `Pending` 是已知 preview 问题，不单独判失败；Pod 到 data plane 的实际订阅资格及故障行为仍为 **Inconclusive：未执行故障验证**。
- **推荐库与执行分开：** 服务自动推荐 library 有 25 个 Scenario，逐个检查 configuration 总数为 **0**；此次未创建用户 Scenario/configuration，也未运行故障或业务验证 Job。不要删除自动推荐库来使数量变为 0。
- **清理 Passed：** 已删除临时 runner identity、两个临时 role assignments 和一个临时 custom role；runner identity 恢复为原先未配置身份的状态。临时登录 profile/kubeconfig 已清理，固定版本工具保留。扩展、subscriber identity/federation、Workspace connection 和必要的内置 operator 授权保留。扩展安装后，原 Chaos Terraform 输入 replan 仍为 exit code **0**。
- **跨区域：** [官方区域说明](https://learn.microsoft.com/en-us/azure/chaos-studio/chaos-studio-region-availability#regional-availability-of-chaos-studio-workspaces)允许 Workspace 发现并针对任何 Azure region 的资源运行 Scenario；UK South Workspace 与 UAE North AKS/PaaS 无需同区域。PaaS 的具体 resource type、SKU、Action 和执行权限仍需分别核对；本次不授予 PaaS 故障执行权限，也不声称 PaaS 故障已验证。
- 私有 inputs、plans、日志、安装状态和真实标识保留在操作员私有目录；不复制到公开文档或 PR。Terraform backend 仍为原有独立 Chaos state。

#### 私有 API 连通后继续安装

先恢复操作端到 AKS 的已批准 VPN/VNet 连接与 private DNS，或使用已有权限、网络及可信身份的管理执行端。不要为了继续安装而默认调整 NSG、公共访问或 cluster policy。

以下从仓库根目录、具有正确 platform/Chaos state 访问的操作端执行。当前操作员的 CLI 扩展安装在 `$HOME/private/chaos-cli-extensions`；换执行端时，应先从官方源安装相同版本并核对 checksum，而不是直接使用 latest。

```bash
set -euo pipefail
umask 077
export AZURE_EXTENSION_DIR="$HOME/private/chaos-cli-extensions"

AKS_RG="$(terraform output -raw resource_group_name)"
AKS_NAME="$(terraform output -raw cluster_name)"
AKS_ID="$(terraform output -raw cluster_id)"
SUBSCRIPTION_ID="$(printf '%s' "$AKS_ID" | cut -d/ -f3)"
WORKSPACE_ID="$(terraform -chdir=stacks/chaos output -raw workspace_id)"

export KUBECONFIG
KUBECONFIG="$(mktemp "$PWD/local-state/dev/private/chaos-install.XXXXXX.kubeconfig")"
trap 'rm -f "$KUBECONFIG"' EXIT
az aks get-credentials --subscription "$SUBSCRIPTION_ID" \
  --resource-group "$AKS_RG" --name "$AKS_NAME" \
  --file "$KUBECONFIG" --format exec --output none
kubelogin convert-kubeconfig --login azurecli --kubeconfig "$KUBECONFIG"

# DNS/API/权限失败时停止；只有明确 NotFound 才创建独立空 namespace。
target_namespace="$(kubectl --request-timeout=30s get namespace chaos-targets \
  --ignore-not-found --output name)"
if [ -z "$target_namespace" ]; then
  kubectl create namespace chaos-targets
fi
```

此 namespace 不部署业务 workload，不修改 admission policy。确认 namespace、权限和扩展未被其他 state/操作员管理后，才运行安装命令。`0.1.12` 是本次 catalog 核对值；后续安装时重新核对可用性，再显式固定版本，不盲目复制失效版本。

```bash
az k8s-extension create \
  --subscription "$SUBSCRIPTION_ID" \
  --resource-group "$AKS_RG" \
  --cluster-name "$AKS_NAME" \
  --cluster-type managedClusters \
  --name chaos-studio \
  --extension-type Microsoft.ChaosStudio \
  --release-train dev \
  --version 0.1.12 \
  --configuration-settings \
    "chaos-workspace-id=$WORKSPACE_ID" \
    "experiments.targetNamespaces[0]=chaos-targets" \
  --output none
```

安装流程拥有 extension、subscriber identity/federation、内置 operator role assignment 和 Workspace connection；不要再通过 Terraform 重复创建。不要覆盖安装流程管理的 subscriber、identity 或 daemon 参数；安全策略导致 network component 未启用时，记录限制，不自动添加 policy 例外。

仅检查安装状态，不启动任何 Scenario：

```bash
az k8s-extension show --subscription "$SUBSCRIPTION_ID" \
  --resource-group "$AKS_RG" --cluster-name "$AKS_NAME" \
  --cluster-type managedClusters --name chaos-studio \
  --query provisioningState --output tsv
kubectl --request-timeout=30s get pods --namespace chaos-infrastructure
```

需要 extension provisioning `Succeeded` 及组件 readiness 证据。Workspace connection 的已知 `Pending` 问题不单独作为失败/成功判据。此次不创建/启动故障，也不以短故障“验证安装”；实际故障能力、private-cluster 资格和业务恢复仍为 **Inconclusive：未执行，须后续单独授权**。

<a id="optional-remote-state"></a>

## 6. 可选：远程 state

默认本地工作流跳过本节。

- 在相应阶段 root 创建 `backend_override.tf`，内容如下；按 [私有配置样例](../environments/dev-platform.azurerm.backend.hcl.example) 分别填写配置并使用独立的阶段 `key`，不共享同一 state。

```hcl
terraform {
  backend "azurerm" {
    use_azuread_auth = true
  }
}
```

- 远程配置必须填写真实的 RG、Storage account、container、独立阶段 Blob `key`、subscription、tenant，并使用 `use_azuread_auth = true`；不使用存储访问 key。
- 真实配置文件准备好后，才给相应 `init` 添加 `-backend-config=<实际文件路径>`。目录不是文件，样例占位值不是可部署配置。
- 远程存储独立准备；需要新建时才使用 [Bootstrap stack](../stacks/bootstrap/)。切换已有 backend 前备份、停止并发并取得迁移授权，不能用空 state 绕过问题。

## 7. 部署后验证与故障运行

- 在云端 AKS 验证私有 DNS、路由、TLS、应用身份及业务读写；资源创建成功不等于业务通过。
- 调查重复 plan 的非预期变更；不删 state、不销毁共享资源，也不扩大权限或开放公网来绕过问题。
- 故障运行需单独授权目标、影响上限、持续时间、停止条件及恢复步骤。Terraform 配置不自动启动故障。
- 故障后确认真实连通性和已确认数据完整性，再重新 plan 检查 drift。停止故障或报告 `Succeeded` 不等于业务已恢复。

<a id="chaos-test-operations"></a>

## 8. 全部 Chaos 测试操作 Runbook

### 8.1 项目内的代码、配置与证据

| 内容 | 唯一日常使用位置 |
| --- | --- |
| 原生执行、Validate、恢复观察、脱敏汇总 | [run_native_case.py](../modules/chaos-validation/run_native_case.py)、[validate_native_targets.py](../modules/chaos-validation/validate_native_targets.py)、[observe_native_run.py](../modules/chaos-validation/observe_native_run.py)、[summarize_native_runs.py](../modules/chaos-validation/summarize_native_runs.py) |
| Terraform 资源声明与状态 owner | [Chaos 模块](../modules/chaos/)、[Chaos stack](../stacks/chaos/)；原 `local-state/dev/chaos.tfstate` 不移动、不复制成第二个 owner |
| 十二项原生配置脱敏样例 | [native-chaos.example.tfvars.json](../environments/native-chaos.example.tfvars.json)；仅作输入说明，所有占位符必须替换，破坏性配置开关默认关闭 |
| 当前完整真实配置、Workspace、catalog | `local-state/dev/chaos-testing/native-chaos.private.tfvars.json`、`native-workspace-current.private.json`、`regional-catalog.private.json` |
| 实际 run journals、验证、健康、审计与 replan | `local-state/dev/chaos-testing/native-test-runs/` 及同目录证据文件；原九项完整记录已落地，SHA256 与报告一致 |
| 历史检查脚本、输入与快照 | `local-state/dev/chaos-testing/history/`，迁移校验为 `transfer-manifest.private.json`；只作追溯，**不要直接执行旧安装、临时权限、Run Command 或 cleanup 脚本** |
| 可选 HTTPS/业务验证及独立账本 | [probe.py](../modules/chaos-validation/probe.py)、[business.py](../modules/chaos-validation/business.py)、[ledger.py](../modules/chaos-validation/ledger.py)、[stop.py](../modules/chaos-validation/stop.py)、[campaign.py](../modules/chaos-validation/campaign.py)，其 [JSON 样例与 SDK 锁定文件](../modules/chaos-validation/) 均已在项目 |
| 用例、人工审查报告 | [70 项唯一清单](./chaos-test-and-coverage-plan.md)、[实际原生测试报告](./chaos-studio-native-test-report.md) |

`local-state/` 已被 Git 忽略，真实配置和原始证据只保留权限 0600、目录 0700；不要 `git add -f`。会话内原件仅作备份，日常操作不再依赖会话路径。SDK/Provider 下载缓存、安装工具、临时 kubeconfig、凭据和旧临时基础设施不是测试源代码，不复制进版本控制；当前 Terraform owning states 保留原位置。

准备独立目录，并先运行**无 Azure 调用**的输入检查：

```bash
umask 077
install -d -m 700 local-state/dev/chaos-testing
python3 modules/chaos-validation/run_native_case.py --check-inputs
python3 -m unittest discover -s modules/chaos-validation/tests -p 'test_native.py'
```

此目录已经有当前十二项完整配置；**不要用初始空 `scenarios` 样例覆盖它**。其它已批准环境使用 `--config-dir <项目内独立目录>`，保持各环境的配置、日志、state/backend 分离；不要复制当前资源 ID 作为其它环境的默认目标。新测试 cohort 使用新目录，经授权复制匹配的输入/Workspace/catalog，不删除原 journal 来重试。脚本不创建 Workspace/Scenario、不安装 agent、不修改 RBAC。

换操作端时，通过批准的私有传输获取这些输入；`native-workspace-current.private.json` 至少包含实际 `id`。catalog 必须来自相应区域的官方 Action API，并核对所选 version/schema；可在私有终端刷新，完整分页结果保存到 `regional-catalog.private.json`，不能只保存第一页或把 catalog 当执行许可：

```bash
# SUBSCRIPTION_ID、WORKSPACE_LOCATION 从已审查的私有输入读取，不在命令历史硬编码。
az rest --method get \
  --url "/subscriptions/${SUBSCRIPTION_ID}/providers/Microsoft.Chaos/locations/${WORKSPACE_LOCATION}/actions?api-version=2026-08-01-preview" \
  > local-state/dev/chaos-testing/catalog-first-page.private.json
```

有 `nextLink` 时继续 GET 并合并 `value`；真实上下文/API 不匹配或 schema 未确认时停止。本轮已经保留验证过的完整 catalog，无需为了整理文件重新请求云端。

### 8.2 每次测试的共同步骤

1. **选用例与层级：** 核对 Case ID、产品/variant、原生能力及准备状态。九项脚本允许列表不包含 forced、flush、VM/AKS 故障；其它场景按 §8.5 补前置、另审范围，不能改名冒充。
2. **确认授权：** 记录现有目标、最多一资源/实体/实际实例、参数、影响、持续时间、停止阈值、恢复权限和负责人。配置/Validate 不授权 Execute。共享资源和生产默认排除；目标 RG 与唯一批准的 AKS node RG 例外分开。
3. **核对环境：** 检查 subscription/tenant、已有 Workspace、原 owning state、RBAC 与当前支持 schema；只用精确输入。不得为方便开放 private AKS、公网端口、共享 NSG，或增加订阅级权限。
4. **检查关联：** 在 Workspaces → 指定 Workspace → Scenario → `approved-targets` 查看明确目标。缺发现快照先走第 5 节 `/discover`。这是 Workspace 模型，不是 classic Targets/capabilities；一个 VMSS 不是一个节点。
5. **Validate：** 核对单 Action、参数、`PT1M`、资源/region/zone、System/恢复及 production tag 排除，要求当前 Validate `Succeeded` 且只解析获批目标。权限传播问题先核对实际 assignment，有限重验；不自动修复权限。
6. **基线：** PaaS Resource Health 必须 Available，数据库 Ready / HA Healthy，queue/hub 原状态 Active；记录角色/zone、实体状态。管理面成功不是应用基线；完整业务层另采请求、延迟和独立数据账本。纯原生阶段不强制新建业务应用。
7. **排除并发：** 查看 Workspace 全部 Scenario 的 Runs，不能有非终态运行；只串行运行一项，相互重叠的故障禁止并发。实验期间暂停会反复纠正临时状态的自动化，但不永久屏蔽 drift。
8. **一次 Execute：** 明确授权后单次启动，记录执行意图、响应、run ID、实际解析目标和请求时间。POST 超时/202 结果不明时不重发；先查 Runs 和 journal。`PT1M` 不是实际服务中断/动作完成时长。
9. **观测与停止：** 保存 run/Action、目标事件与管理面采样；运行停止阈值 15 分钟，API 超时/重试仍可能使一次观测延迟，操作员须独立监控。GET 瞬时失败最多三次；POST Execute 不自动重试。越界、完整性异常、控制路径受损、指标超过约定阈值或监控失效立即停止批次并按 §8.4 处理。
10. **恢复：** 等终态并核实目标 Action 非 Skipped、确实命中目标；十分钟共同恢复预算内要求原实体状态 / 数据库 Ready、HA Healthy 和 Resource Health Available。数据库角色/zone 可能变化，不暗中 failback。Resource Health 滞后时继续记录，不能先开始下一项。
11. **报告与 drift：** 保留 hashes、完整时间线、缺失证据、停止恢复记录；管理面、真实影响、完整 infra/business 各自判定。恢复后按 §8.6 原 Chaos state 和完整输入 replan。失败/证据不足不计 Passed；清理仅限自有临时文件/资源，不销毁共享目标或 backend。

### 8.3 九项已验证原生流程：逐项参数与恢复

下表每行单独执行 §8.2，不同时组合故障。配置与曾经运行成功不授权下一次重跑。

| Case ID | Scenario / 参数 | 运行中与恢复检查 |
| --- | --- | --- |
| B-01 | `b01-servicebus-send-disabled`；`desiredState=SendDisabled`、`queues` 为一个既有实体的 JSON 数组 | 先 Active；观察 SendDisabled；结束恢复原 Active。后续业务层核对 publish ack/unknown、积压和唯一 effect |
| B-02 | `b02-servicebus-receive-disabled`；`desiredState=ReceiveDisabled`、同样精确 queue | 观察 ReceiveDisabled；恢复 Active。业务层另看 PeekLock、settlement、重复/DLQ，不把队列 write 成功当消息保证 |
| H-01 | `h01-eventhub-send-disabled`；`desiredState=SendDisabled`、`eventhubs` 为一个既有实体的 JSON 数组 | 观察 SendDisabled；恢复 Active。后续核对 partition producer ack/unknown，不宣称全局顺序 |
| H-02 | `h02-eventhub-disabled`；`desiredState=Disabled`、精确 hub | 观察 Disabled；恢复 Active。后续检查 consumer effects/offsets/checkpoints/replay，不宣称 exactly-once |
| M-02 | `m02-mysql-restart`；无参数，Discrete | 记录 Ready→Restarting→Ready、HA Healthy、Resource Health Available、主/备角色与 zone；已有 restart 不因观察超时重发 |
| P-01 | `p01-postgresql-planned-failover`；`FailoverMode=PlannedFailover`、`RestoreOnStop=false`、`SkipIneligibleServers=false` | 观察 Updating / standby 重建；确认 Ready、HA Healthy、Resource Health Available；RP 使用 restart/action 不等于普通重启测试；不自动切回 |
| M-01 | `m01-mysql-ha-failover`；`RestoreOnStop=false`，Cancelable | 记录故障前后角色、zone、Updating/Ready 和 HA；恢复可用不要求暗中切回原 zone，数据层另核验 |
| R-02 | `r02-legacy-redis-secondary-reboot`；`RebootType=SecondaryNode`，Discrete | 仅 Legacy Redis 单 secondary；核对原生 action、平台健康，补节点/副本事件与实际复制恢复证据；无直接影响证据为 Inconclusive |
| R-01 | `r01-legacy-redis-primary-reboot`；`RebootType=PrimaryNode`，Discrete | 仅单 primary，不使用 AllNodes；另确认节点/角色、复制和真实连通。`provisioningState=Succeeded` 不证明已发生 reboot |

先只做原生 preflight（会 POST Validate，但**不 Execute**）：

```bash
python3 modules/chaos-validation/validate_native_targets.py
python3 modules/chaos-validation/run_native_case.py b01-servicebus-send-disabled
```

第一条验证当前完整十二项配置，也可传一个或多个 Scenario 名限制选择；不会运行它们。第二条仅对一项核对参数、精确 target/exclusions、当前验证、无并发、基线与 Resource Health。

只有新 cohort 的明确运行/恢复授权成立后：

```bash
# 用已经批准的新 cohort 项目目录替换示例路径；不删除旧 evidence。
python3 modules/chaos-validation/run_native_case.py b01-servicebus-send-disabled \
  --config-dir "$PWD/local-state/dev/chaos-testing-next" --execute
```

完成并确认恢复后，再用表中的下一项 Scenario 名执行。默认目录包含本次九项既有 journals，脚本会拒绝 `--execute` 重放。脚本失败会停止当前调用；它不批量追赶、不自动执行后续场景。异常时可取消的**已知自有 run**会走原生 cancel；终态后仅在既有恢复许可下恢复原 queue/hub 状态，数据库/Redis 不自动重启或 failback。

### 8.4 观察中断、取消和恢复

**仅恢复同一个 run 的观察：**

```bash
python3 modules/chaos-validation/observe_native_run.py m02-mysql-restart
python3 modules/chaos-validation/observe_native_run.py p01-postgresql-planned-failover
```

此脚本校验保存的 run/Scenario/目标/原参数与基线，只有 GET，不 Execute、不 cancel、不修改云端资源；必要时继续十分钟恢复检查。已完成的 journal 不改写、不请求 Azure，保留报告 SHA256。run ID 缺失或有多个新 run 时，先在原 Scenario 的 Run history 查明唯一身份并人工复核，不删除/重置 journal。不可证明时保留 Inconclusive，不能发新故障验证旧结果。

**停止步骤：**

1. 停止后续调用，保存当前自有 run/status/解析目标与告警。
2. 在 regional catalog 确认该 Action 是 Cancelable，或按其 Continuous 停止语义处理。Discrete restart/reboot 已开始后不承诺能取消；不能把所有场景都看成可撤销。
3. 已授权取消且确认是自己的 run 时，优先 Portal 指定 run → Cancel。REST 等价操作只对已核实的 `RUN_ID`：`POST ${RUN_ID}/cancel?api-version=2026-08-01-preview`，无 body；按 Location 轮询异步结果，再 GET 同一 run 至 Succeeded/Failed/Canceled，非终态不能视为已停。
4. Cancel 不等于业务恢复。queue/hub 在终态后仍非原状态时，只在明确恢复许可下恢复**同一实体的原状态**，随后 GET 核验；不改整个 namespace，不调用权限自动修复。
5. 数据库等待 Ready/HA Healthy 和 Resource Health Available，保留所有不健康采样。MySQL 观察中断、PostgreSQL Ready/Healthy 但首次 Resource Health Unavailable 的本次记录都已保留；健康证据恢复前不能继续批次。
6. VM/node/Pod/网络故障按对应已授权恢复方案核查真实 workload、连通、调度及数据；停止成功但网络仍残留时记录失败并恢复获批对象，不重启整个集群或改共享网络。

恢复仍超预算或资源/数据状态不明时升级操作员处理并记 Failed/Inconclusive；不追加新故障、不 `terraform destroy`、不重放 Execute。

### 8.5 其余 61 项的操作分支（加上 §8.3 共 70 项）

这些用例都先执行 §8.2 的**选择、支持、范围与授权检查**。未满足对应分支时停在准备阶段，记 NotRun 和具体缺项；本表不授权安装、拓扑修改、业务流量或破坏性动作。

#### 原生能力存在，待前置/范围确认：15 项

| Case ID | 补齐后才可继续的步骤 |
| --- | --- |
| P-02 | 另批 forced failover/数据与恢复风险 → 核对既有 `p02-postgresql-forced-failover`、ForcedFailover 参数与 HA → Validate → 单次 Portal Execute → 记录数据/角色/健康恢复；不借 P-01 脚本运行 |
| V-09 | 确认 broker 及所有间接消费者中断许可/备份 → 基线 guest、服务和恢复 → 核对 `v09-private-vm-restart` 的单 VM → Validate/授权 Execute → 核对 VM running、guest、broker/store 及消费者恢复 |
| N-07 | 从 AKS `nodeResourceGroup` 属性映射 User VMSS → 重新枚举 zone 的真实实例，须恰好一个 → 核验剩余容量、workload/存储/副本放置 → 确认 `n07-single-user-node-shutdown` 的 region/zone/GracefulShutdown → Validate/独立授权 → 恢复实例、节点/Pod/业务；排除 System |
| V-03, V-04 | 核验现有 VM identity、受支持 OS/架构、public outbound、headroom 与恢复 → 获批补前置 → 单 VM 小强度短时 CPU/memory 场景 → Validate/授权 Execute → 核验 guest/服务。原生运行自动安装并保留 agent，不手装 classic agent、不开放网络 |
| K-01, K-02, K-03, K-04, K-05 | 使用已有私网操作端 → 核验 Linux/架构/Kubernetes/OIDC/WI/RBAC/扩展及当前 namespace AND labels 的获批 workload → 核验 subscriber/控制组件/恢复路径 → 分别定义 Pod delete/CPU/memory/latency/loss 单 Action → Validate/独立授权与真实功能验证。private AKS 是未验证配置，不当作明确不支持，不新建应用补数量 |
| N-01 | 单独批准整个 zone 的影响 → 确认所有实际实例、跨 zone 放置、剩余容量与存储 → 新建精确 VMSS/zone 配置 → Validate/单故障/恢复；不复用 N-07 单节点授权 |
| N-02, N-03 | 先确认 VMSS CPU/memory Action 的精确实例边界、身份/出站和备用容量 → 仅获批实例的配置与权限 → Validate/授权 Execute → 节点/业务恢复；未证明单实例时不压整池 |
| B-03 | 选现有独立 topic/subscription → 核对当前 Action/schema/状态恢复许可 → 配置对应实体与最小权限 → Validate/单次 Execute → 恢复原状态并检查投递；queue 结果不替代 |
| A-02 | 确认 Managed Redis 专用数据库与全部数据可重建 → 单独批准不可撤销 flush 与重建 → 核对 DatabaseName/目标/Action → Validate/Execute → 重建并核对源数据；不把 Legacy reboot 当 flush |

#### 已证实当前目标不兼容：2 项

| Case ID | 停止条件与下一步 |
| --- | --- |
| S-03 | 当前 Standard_ZRS 不具备 geo planned failover 前置，记 Blocked 并附 SKU 证据；不升级冗余或迁移存储来凑用例。另选获批合格目标后重新设计恢复 |
| A-04 | 当前没有 geo links，记 Blocked 并附拓扑证据；不自动创建伙伴/force-unlink。新增拓扑与 unlink 恢复须单独审查 |

#### 精确故障尚未映射等价原生 Action：25 项

| Case ID | 本轮步骤 / 不得替代的语义 |
| --- | --- |
| C-01, C-02, C-03, C-04, C-05 | 分别确认协议与单依赖的 blackout、latency、unknown ack、局部 DNS、throttle；核对官方当前 schema/目标/作用域。未找到等价原生动作就记 PendingDesign/NotRun，不改共享 NSG 或用 Pod-wide 故障冒充 |
| M-04 | 先确认独立 read replica 与其故障机制/作用域；无合格目标/动作则暂缓，HA standby 不是 read replica |
| R-03, R-04 | 查 Legacy Redis 有限 key invalidation/flush 的精确 Workspace 支持；未确认就暂缓，不能套 Managed Redis 的 flush |
| A-01, A-03 | 分别核对 Managed Redis 单客户端断连/客户端 regional redirect；flush/unlink 不等价，不执行替代故障 |
| S-01, S-02 | 明确 interrupted transfer/客户端 secondary fallback 和支持的冗余拓扑；当前未映射，S-02 的 secondary 前置也不满足。SDK upload/hash 检查不是故障注入 |
| B-04, H-03, H-04 | 明确 commit→settlement、commit→checkpoint 或独立 consumer pause 的可控时序/机制；实体 Disabled 不证明该间隙，未确认机制就暂缓 |
| K-06 | 确认递增内存泄漏的真实模型与单 Pod 边界；固定 memory hog 不等价，不用 K-03 成绩代替 |
| V-05, V-06, V-07, V-08, V-10 | 分别核验 VM 精确路径 latency/loss、专用卷 exhaustion/IO、精确 guest 进程终止的当前原生机制和恢复。未映射则暂缓，不杀 broker、不填满共享磁盘 |
| N-04, N-05, N-06 | 核验 node-wide loss/latency/API partition 的实际节点作用范围；Pod-only 结果不替代，不改共享 NSG/AKS API 路由 |
| I-01 | 先确认现有 ASM/Istio 目标与 control/data partition 机制；未选 mesh 或动作未映射则暂缓，不安装 mesh 补齐 |

#### 服务专项、未选或未来：19 项

| Case ID | 操作分支与授权边界 |
| --- | --- |
| M-03, P-03, S-04, B-05, H-05, H-06 | PITR、Blob protection、regional/Geo-DR/Geo-Replication 是服务专项：先批准新资源/数据恢复/切换范围 → 核对原生服务方案 → 独立隔离恢复演练与对账 → 清理自有资源；不写成已经支持的 Chaos Workspace Action |
| D-01, D-02 | Cosmos 本轮 Unselected；选用后核对 consistency/write mode、partition key/region、ack/unknown/ETag/session 与恢复，再审相应 Action。D-02 有 offline-region 不授权扩 region |
| V-01, V-02 | RocketMQ durability 本轮 Unselected；另选业务层后核对实际 flush/replication、publish ack、consumer commit/ack 与 retry/DLQ/唯一 effect，VM restart 不证明 broker 保证 |
| L-01, L-02, L-03, G-01, G-02, G-03 | 当前无获批 LB/Gateway，记 Future；先选择独立 owner/目标及当前原生机制，再核验 backend/probe/路径与恢复，不接管或故障化 AKS 托管 LB |
| E-01, E-02, E-03 | 完整多依赖业务层 Deferred；先接已有应用契约、独立账本与 SLO/stop/recovery → 单组件通过后再分别授权组合与分阶段恢复，不能从九项管理面成功推导业务通过 |

### 8.6 证据、报告与恢复后 plan

默认目录已经保留当前九项 run 原件、健康/审计快照、完整输入及原 replan 日志。下面**仅离线汇总**，不访问 Azure、不改 journal、不覆盖已审查报告：

```bash
python3 modules/chaos-validation/summarize_native_runs.py \
  > local-state/dev/chaos-testing/native-run-review.private.json
python3 modules/chaos-validation/summarize_native_runs.py --markdown \
  > local-state/dev/chaos-testing/native-run-review.md
```

新 cohort 汇总时传相同 `--config-dir`。报告审查还要补 run/Action 目标一致性、执行授权、审计覆盖/延迟、停止与恢复、原始观测缺口。公共报告使用 Case ID、时间、状态与 SHA256，不发布 ARM IDs、真实实体名、端点、run/request IDs、凭据或原始日志。管理面 Passed 只限可直接观察的状态/恢复，Redis 没有节点影响证据为 Inconclusive；完整 infra/business 不被脚本自动判 Passed。

当前结果参考[已审查报告](./chaos-studio-native-test-report.md)。若需要新一轮报告，应人工更新其运行范围/日期、九项结果及其余 NotRun 状态，不把历史快照称作云端实时健康。

恢复后，只对原 Chaos owner 用完整输入生成新 plan，私下审查 create/update/delete/replace 和 RBAC/filters；不要 apply 来“纠正”正常故障中暂时状态：

```bash
terraform -chdir=stacks/chaos plan -input=false -detailed-exitcode \
  -var-file="$PWD/local-state/dev/chaos-testing/native-chaos.private.tfvars.json" \
  -out="$PWD/local-state/dev/private/dev-chaos-post-test.tfplan"
```

0 无变化、2 有变化待审、1 错误；Chaos 无漂移不证明完整 Platform 或数据恢复。没有新部署授权不 apply；不用 `-target`、空 state 或 `ignore_changes` 扩大掩盖问题。

### 8.7 后续可选业务/AKS 验证（不作为本轮原生前置）

这些源代码和配置已经在项目，完整 contract、限时、资源 requests/limits、固定镜像 digest、独立停止路径与真实 durable ledger 资格须先满足。**Job 默认只运行 probe.py，不能因 ConfigMap 包含 business.py 就称业务流已运行。**

1. 将 [campaign.example.json](../modules/chaos-validation/campaign.example.json) 与 [business.example.json](../modules/chaos-validation/business.example.json) 复制到项目私有 cohort 目录，填写已有应用/实体、数据权限、phase 和独立账本路径；使用已批准 projected workload identity，不复制个人 token/密码。
2. 离线检查：`python3 modules/chaos-validation/campaign.py --manifest <私有文件>`、`python3 modules/chaos-validation/business.py --config <私有文件>`。case registry 识别 70 项不是 70 项 client/fault 都已实现。Blob、Service Bus 合成参考流已实现，其它真实应用流暂未实现。
3. 如需 SDK 检查，在项目内隔离 venv，按 [hash-locked requirements](../modules/chaos-validation/requirements-business.txt) 安装到开发/构建环境；云端使用已批准固定 digest 工具镜像，不在 Job 启动时安装 latest。不要把 `.venv` 或下载的 SDK 源码提交。
4. 从已有获批私网执行端核验 AKS private DNS/CA/TLS/认证、实际 workloads、独立 verifier/recovery placement；不新建公网访问，不默认安装临时身份或启用 AKS Run Command。按第 4 节单独审查 cluster 配置，Job/流量需要单独授权。
5. 云端 baseline → exposure → recovery 分阶段运行 [模块说明中的限时命令](../modules/chaos-validation/README.md#before-authorized-traffic)，留存 ack/unknown、哈希、producer/consumer attempt、唯一 effect 与 settlement/checkpoint。真实业务逐产品遵循唯一清单的事务/cache-aside/传输/消息/一致性契约，不以合成参考流代替。
6. 对已经授权的 streaming Job，独立 `kubectl logs --follow ... | STOP_POLICY=... python3 modules/chaos-validation/stop.py` 评估停止信号；窗口、silence 和 monitor-failure 必须核验。它不执行 cancel，非 Passed 需要操作员停止/升级处理。
7. 原 cohort 恢复用 `business.py --verify-existing`，不重发 producer；它会读取/消费/确认已知消息，需要相同服务访问授权。纯离线 `--reconcile` 不调用服务。完整生产者中断、未知确认、未 settlement 或缺 effect 不能判通过。
8. 用 `campaign.py --recovery-jsonl <私有日志>` 核对各约定恢复窗口，再独立验证真实数据、RTO/RPO、后续回归及 drift。保留账本/WAL 与证据在注入路径外的云端 durable volume，并安全导出到项目私有存储后才清理自有 Jobs；项目本地文件不替代云端独立 durable ledger。

### 8.8 2026-11-23 使用项目代码重新执行

用户再次授权后，使用独立项目目录 `local-state/dev/chaos-testing-rerun-20261123/`，保留首轮 `chaos-testing/` 的输入、九项 journals 和 SHA256。新目录只复制匹配的完整 Terraform 输入、Workspace 与已验证 catalog；不复制旧 run journals、不删除旧记录。

本轮直接调用项目中的 `run_native_case.py`，不是会话脚本、SDK 流量或模拟故障。五个 PaaS Resource Health 先检查为 Available，当前无活动运行；项目 `validate_native_targets.py` 对全部十二项配置实时验证成功，完整 Python 单元测试73项通过。运行前 ARM 核验 private AKS 仍为 true。运行范围仍仅九项 bounded PaaS；forced、flush、VM/节点/Pod 与网络未扩展。

本轮入口（已运行的命令，**不作为再次执行授权**）：

```bash
cohort="$PWD/local-state/dev/chaos-testing-rerun-20261123"
python3 modules/chaos-validation/run_native_case.py --config-dir "$cohort" --check-inputs
python3 modules/chaos-validation/validate_native_targets.py --config-dir "$cohort"
# 每次只执行一个已授权 Scenario；前一项成功并恢复后才进入下一项。
python3 modules/chaos-validation/run_native_case.py b01-servicebus-send-disabled \
  --config-dir "$cohort" --execute
```

九项顺序为 B-01 → B-02 → H-01 → H-02 → M-02 → P-01 → M-01 → R-02 → R-01。每项日志为同目录 `<scenario>.run.private.log`，原始记录为 `native-test-runs/<scenario>.private.json`；`campaign.private.json` 记录运行范围与本轮四个项目脚本的 SHA256。已存在 journal 时，脚本在任何新 Azure 调用前拒绝重放。

若当前 cohort 的观察被中断，明确指定同一目录，不误读首轮默认目录：

```bash
python3 modules/chaos-validation/observe_native_run.py m02-mysql-restart \
  --config-dir "$cohort"
python3 modules/chaos-validation/observe_native_run.py p01-postgresql-planned-failover \
  --config-dir "$cohort"
```

本轮九项已全部完成：11:24:31–11:55:14，9/9 run/Action Succeeded，7项管理面 Passed、Redis 两项 Inconclusive，完整业务未验证。P-01 原生成功后 Resource Health Degraded，交互中断终止了控制端批次；使用项目 observer 指定同一目录、同一 run 核验到 Available 后，只继续未启动的后三项，没有重放 Execute。没有用源码修改、取消或手工实体恢复来掩盖结果。

最终独立 GET 复核每个新增 run 的唯一 Action/目标、执行前后只新增一个 run、五个 PaaS Available、数据库 Ready/HA Healthy、queue/hub Active、无活动运行和 private AKS=true。完整输入/原 Chaos state replan exit code 为0，未 apply；当前项目代码的实际可行性、秒数/hash 和审计见[原生报告 §7](./chaos-studio-native-test-report.md#7-当前项目代码实际重跑结果)。首轮记录不被覆盖。

本轮追加 private AKS 检查：ARM/MCP 集群已与用户指定目标核对一致；User/System 各两个真实实例，zone-2 User 目标当前匹配一个；N-07 已原生 Validate。但当前操作端 private DNS 不可达，精确 cluster ID 对应的唯一 private endpoint 的既有 TCP 路径也不可达；既有监控近10分钟节点/Pod查询0行，不能推断当前没有 workload 或有足够剩余容量。**尚未启动节点/Pod故障，记 NotRun / PendingVerification，不把 private 本身当不支持。** 不将 Portal 的 Periscope/日志/安全菜单提示当成变更授权。

继续 private AKS 原生测试时，从已有获批私网认证执行端检查：当前节点 Ready / 压力、全部相关 Pod/控制和恢复组件所在节点、副本/存储放置、User spare capacity，以及 namespace AND labels 实际匹配。通过后先执行已有单 User-VMSS/zone 的 N-07，不影响 System；Pod路径另核验扩展/目标/preview功能。不得为继续测试开放 private API、启用 AKS Run Command、改共享网络、复制个人 token 到 VM或未经授权新增临时身份/权限。访问路径、缺失证据与最终执行状态见[原生报告 §8](./chaos-studio-native-test-report.md#8-private-aks-原生测试当前状态)。
