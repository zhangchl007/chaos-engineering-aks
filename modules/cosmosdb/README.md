# Cosmos DB for NoSQL

## 配置与 ownership

保留已有公共输入、输出名称及 Azure 资源 ID；账户、SQL database/container、Private Endpoint 的 address 增加 `[0]`，提供 `moved` blocks 迁移旧地址，不通过删 state 重建。DNS/link/命名资源地址保持不变。RG、VNet、subnet 由调用方管理；`subnet_ids["privateendpoint-subnet"]` 必须是已有、非委派 Private Endpoint subnet 的 Azure ID，不回退 node subnet。DNS VNet link 由该 endpoint subnet 推导 VNet，不再依赖 `node-subnet`。模块继续拥有原有 `privatelink.documents.azure.com` zone 与 link；同一 RG 不可重复部署并接管同名 zone。启用账户时，Private Endpoint 的 `Sql` connection 添加 zone group，指向**该模块的** zone，自动维护 DNS records；自定义 DNS / peered VNet 的转发及额外 link 由调用方负责。

新增 `create_account`（bool、默认 true）保持原默认行为。设为 false 时只管理 DNS zone、VNet link 和 `random_pet`，不创建账户、数据库、容器、endpoint 或 application roles，全部业务 outputs 返回 null。根模块通过 `components.cosmosdb` 控制此参数；`retain_cosmos_network` 默认 false，当前 dev 环境明确设为 true，保留部分部署已经写入 state 的三个前置资源。全新环境同时关闭两个开关时不实例化 Cosmos 模块。

账户、数据库和容器使用 `prevent_destroy`：停用开关不是删除数据的授权。若这些业务资源已经存在于 state，禁用可能被保护规则阻止，必须另行审查生命周期；不得通过移除 state 绕过保护。把网络保留开关改为 false 也必须先审查其 DNS/link 删除影响。当前 Azure 中的失败账户不在 state，本轮既不导入也不删除它。

账户固定禁止 local/shared-key authentication、metadata key writes、Azure service ACL bypass，要求 TLS 1.2。新增 `public_network_access_enabled` 为 bool，默认 false，true 被拒绝。所有业务访问都需私网与 Entra ID，不提供任何公共调试例外。继续默认 Session、单区域、400 RU/s container throughput、`/id` partition key。**不提供额外 geo region 开关**，多区域必须单独评估支持、成本、failover 和恢复方案。

`account_location` 可显式覆盖账户及唯一 primary region，默认 `null`，仍沿用 `location`。`location` 必须保持为传入 VNet/subnet 所在区域，用于 Private Endpoint；不能为绕过账户容量限制而移动 endpoint。根模块对应输入是 `cosmos_location`。若收到区域容量不足 / region access 错误，先按[官方步骤](https://aka.ms/cosmosdbquota)申请区域访问，或在确认容量、数据驻留、跨区延迟/费用并批准后指定其他账户区域；不会自动回退。已有账户更改区域可能产生替换/数据迁移，必须重新审查完整 plan，不能删 state 重建。

默认标签按 Azure 不区分大小写的键名规则合并：调用方覆盖匹配的模块默认值，同时保留调用方键名大小写及值。调用方自身含 `Environment` 与 `environment` 等重复别名会在输入校验时报错。

新增可选 `application_principals`：

```hcl
application_principals = {
  workload = {
    principal_id = var.workload_principal_object_id
    role         = "reader" # 或 contributor
  }
}
```

类型为 `map(object({ principal_id = string, role = string }))`，默认 `{}`；使用稳定 key。仅允许明确 Entra **object ID** 与 `reader` / `contributor`，固定 scope 到此模块的 `/dbs/<database>/colls/<container>`，使用 Cosmos 内置 data-plane Reader / Contributor。不授予 Azure control-plane、RG 或订阅权限。不创建工作负载 identity。默认没有 RBAC assignment，调用方必须预先安排身份及权限再执行业务验证；旧 shared-key 客户端需要迁移。

## 状态与覆盖

M/P = mocked-provider / plan-only，不访问 Azure；使用 Terraform 1.15.6 的 plan-time mock 功能。父模块负责锁定 AzureRM **4.55.0** 与 random provider、初始化和认证；子模块只声明 source，去除不兼容的 3.x 约束。

| case | 配置/测试 | 结果 |
|---|---|---|
| 私有账户、禁 key/bypass、endpoint DNS、默认账户/endpoint 同区域、单区域、默认无 RBAC | `private_single_region`（M/P） | Passed |
| 仅保留 DNS/link/命名，无业务资源/RBAC，业务 outputs 为 null | `network_only_has_no_business_resources`（M/P） | Passed |
| 显式账户区域覆盖保留 endpoint 区域；标签大小写覆盖与值保留 | `account_region_override_and_caller_tags`（M/P） | Passed |
| 明确 principal 的 container-only Reader | `explicit_container_reader`（M/P） | Passed |
| 非法 subnet、公网开关、重复大小写 tag、空账户区域 | 四个 reject case（M/P） | Passed |
| 禁止 broad/control-plane role | `reject_broad_role`（M/P） | Passed |
| DNS records、实际 Entra RBAC、网络恢复、数据完整性 | 云端授权验证 | Blocked：本变更未执行云操作 |

初始化后，在本目录执行 `terraform test`。M/P 不验证 DNS record 实际生成或权限传播。关闭现有公网与 local auth 可能中断旧客户端；先迁移身份、确认 VNet 连通和 DNS，再审查部署 plan。迁移已有资源时不得通过删除 state 重建。

Schema 核对：2026-11-20，官方 AzureRM v4.55.0 [account](https://github.com/hashicorp/terraform-provider-azurerm/blob/v4.55.0/website/docs/r/cosmosdb_account.html.markdown)、[container](https://github.com/hashicorp/terraform-provider-azurerm/blob/v4.55.0/website/docs/r/cosmosdb_sql_container.html.markdown)、[Private Endpoint](https://github.com/hashicorp/terraform-provider-azurerm/blob/v4.55.0/website/docs/r/private_endpoint.html.markdown)、[SQL role assignment](https://github.com/hashicorp/terraform-provider-azurerm/blob/v4.55.0/website/docs/r/cosmosdb_sql_role_assignment.html.markdown)。
