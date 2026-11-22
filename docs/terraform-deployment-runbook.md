# Terraform 部署 Runbook

所有命令从仓库根目录执行。项目流程：**Platform → 按需配置 Cluster → Chaos Studio Workspace / Scenario → 单独授权故障运行**。Bootstrap 和远程 backend 可选；Chaos Studio 是项目主流程，不是被省略的附属步骤。

## 1. 准备

- 使用 Terraform 1.15.6 和仓库锁定的 Provider；保留各阶段 `.terraform.lock.hcl`，不使用 `-upgrade`。
- 确认 Azure 身份、订阅和目标环境。人工使用 Azure CLI 登录；CI 使用独立的 federated identity，不依赖个人会话。
- 保留已有 state，变更前私下备份，避免并发操作。切换 `.tfvars` 不会切换 state；已有 backend 迁移必须另行授权。
- state、私有输入、密码和计划均按敏感文件保护，不提交或公开。禁用组件可能删除已有资源，必须审查 plan。

```bash
umask 077
install -d -m 700 local-state/dev "$HOME/private"
```

| 阶段 | 默认 state | 计划文件 |
| --- | --- | --- |
| Platform | `local-state/dev/platform.tfstate` | `$HOME/private/dev-platform.tfplan` |
| Cluster | `local-state/dev/cluster.tfstate` | `$HOME/private/dev-cluster.tfplan` |
| Chaos | `local-state/dev/chaos.tfstate` | `$HOME/private/dev-chaos.tfplan` |

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
  -out="$HOME/private/dev-platform.tfplan"
```

退出码 **0 = 无变更，2 = 有变更，1 = 错误**。错误时停止，不应用旧计划。本轮只允许新增：已部署平台、PaaS、原有 NSG 的 update/delete/replace 均为 0；出现其它动作先停止调查，不通过删 state 或 `-target` 绕过。

```bash
terraform show -no-color "$HOME/private/dev-platform.tfplan"
```

只有明确授权后，应用审查过的同一计划：

```bash
terraform apply -input=false "$HOME/private/dev-platform.tfplan"
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

path = pathlib.Path.home() / "private/dev-cluster.private.tfvars"
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
  -var-file="$HOME/private/dev-cluster.private.tfvars" \
  -out="$HOME/private/dev-cluster.tfplan"
```

退出码 1 时停止；成功后审查新计划：

```bash
terraform -chdir=stacks/cluster show -no-color "$HOME/private/dev-cluster.tfplan"
```

仅在 plan 成功并明确授权后应用：

```bash
terraform -chdir=stacks/cluster apply -input=false "$HOME/private/dev-cluster.tfplan"
```

随后用相同输入重新 plan。默认组件关闭时只有连接/空验证输出，不表示已安装 add-ons。启用验证 Jobs 会运行请求，必须另行授权测试流量。

## 5. Chaos Studio：创建 Workspace，再配置故障

Chaos Studio 是 Azure 托管服务，不是 Helm chart。此阶段创建 Workspace、专用运行身份和资源发现权限；填写 Scenario 后创建故障配置，**不会启动故障**。

1. 在 Azure Portal 核对 `Microsoft.Chaos` 已注册；未注册时由有权限的管理员明确授权注册。
2. 将 [Chaos 输入样例](../environments/dev-chaos.example.tfvars) 复制到私有目录，填写所有占位值，不覆盖已有配置：

   ```bash
   cp -n environments/dev-chaos.example.tfvars "$HOME/private/dev-chaos.private.tfvars"
   ```

   初次仅创建 Workspace 时，保留 `scenarios = {}`、`permissions = {}`、`aks_extensions = {}`、`pod_scenarios = {}`。已有平台无需重新 init/plan/apply；沿用原有 state/backend。以下 Terraform 命令保持原流程的 `-chdir`、缓存 Provider、readonly lockfile 和 saved-plan 授权方式，不添加 `-upgrade`、`-target` 或 `-auto-approve`。

3. 明确 Workspace 区域和非生产 RG scope。支持区域为 `eastus2`、`westus2`、`westcentralus`、`northeurope`、`swedencentral`、`uksouth`、`japaneast`；Workspace 可跨区管理目标，[UAE North 不是 Workspace 部署区域](https://learn.microsoft.com/en-us/azure/chaos-studio/chaos-studio-region-availability)。区域和数据驻留需确认，不自动迁移目标。
4. 首次初始化只复用平台已有的两个锁定 Provider，然后校验和 plan：

   ```bash
   terraform -chdir=stacks/chaos init -input=false -lockfile=readonly \
     -plugin-dir="$PWD/.terraform/providers"
   terraform -chdir=stacks/chaos validate
   terraform -chdir=stacks/chaos plan -input=false -detailed-exitcode \
     -var-file="$HOME/private/dev-chaos.private.tfvars" \
     -out="$HOME/private/dev-chaos.tfplan"
   ```

   Provider 尚未安装时先走第 2 节的联网安装方式；已经初始化则省略 init。退出码 1 时停止。
5. 审查新计划：初始样例仅创建 Workspace、UAMI 和指定 RG 的 Reader 发现授权，不创建 Scenario 或运行故障。明确授权后才应用：

   ```bash
   terraform -chdir=stacks/chaos show -no-color "$HOME/private/dev-chaos.tfplan"
   ```

   审查完成且明确授权后执行：

   ```bash
   terraform -chdir=stacks/chaos apply -input=false "$HOME/private/dev-chaos.tfplan"
   terraform -chdir=stacks/chaos output -raw workspace_id
   ```

6. 在 Workspace 中核对发现资源；按 [Chaos 模块说明](../modules/chaos/README.md) 填写明确目标、Action 参数、排除项及验证所得的最小权限，再次 plan、审查并授权 apply。Reader 发现权限不是执行故障权限；不要自动授予 Contributor。

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
KUBECONFIG="$(mktemp "$HOME/private/chaos-install.XXXXXX.kubeconfig")"
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
