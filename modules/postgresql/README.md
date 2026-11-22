# PostgreSQL Flexible Server

## 配置与 ownership

新模块仅创建 private PostgreSQL Flexible Server 与 application database，不创建/接管 RG、VNet、subnet、DNS zone 或 link。父模块锁定 AzureRM **4.55.0**，本模块只声明 `hashicorp/azurerm` source，不配置认证。

| input | type | required/default |
|---|---|---|
| `name`, `resource_group_name`, `location` | string | required |
| `delegated_subnet_id`, `private_dns_zone_id` | string | required |
| `administrator_login` | string | required |
| `administrator_password` | string, sensitive | required、私有传入 |
| `sku_name` | string | `GP_Standard_D2s_v3`，仅 GP/MO HA-capable tier |
| `postgresql_version` | string | `"16"` |
| `storage_mb` | number | 32768，限定 provider 支持的离散值 |
| `ha_mode` | string | `SameZone`，仅 SameZone / ZoneRedundant |
| `backup_retention_days` | number | 7，整数 7–35 |
| `database_name` | string | `appdb` |
| `tags` | map(string) | `{}` |
| `public_network_access_enabled` | bool | false；true 被拒绝 |

Outputs：`server_id`、`fqdn`（sensitive）、`database_name`。密码不会输出，但仍可能保存在 state / plan。

`delegated_subnet_id` 必须指向 dedicated subnet，预先委派 `Microsoft.DBforPostgreSQL/flexibleServers`。`private_dns_zone_id` 必须为 `.postgres.database.azure.com` 后缀的现有私有 zone；**调用方必须先建立与 subnet VNet 的 DNS link**。仅引用 zone ID 不能表达 DNS link readiness，根编排必须对真实 link 建立必要依赖。模块不通过 data source 创建/修改网络。

Server 和 app database 使用 `prevent_destroy`，不代替备份与恢复验证。固定 private access、无 firewall bypass、无 geo redundant backup。SameZone 默认降低 zone availability 前提，但不保证目标区域 SKU/HA 配额；ZoneRedundant 必须另行核对。版本枚举对应 provider schema，不代表每个版本仍受服务生命周期支持。缩减 storage、改名及主要版本升级存在替换、不可逆或停机风险，必须审查 plan。本模块不执行故障或恢复操作。

主区 `zone` 与 `high_availability[0].standby_availability_zone` 由 Azure 自动分配/维护；lifecycle 仅忽略这两个字段的后续变更，避免刷新后把 Azure 返回的区号清空，或因 failover 自动切回原主区。**不忽略整个 HA block**：`ha_mode`、网络、身份、密码等配置仍受 Terraform 管理。此策略遵循锁定的 AzureRM 4.55.0 文档，不能代替 HA 健康、可用区拓扑和恢复验证；显式区迁移/failover 必须另行授权。

## 状态与覆盖

M/P = mocked-provider / plan-only，不访问 Azure；测试要求 Terraform >= 1.7。2026-11-20 使用调用方验证的 provider mirror 与 AzureRM 4.55.0 完成 init、validate 和四项 plan-only tests。

| case | 配置/测试 | 结果 |
|---|---|---|
| 私有 subnet / DNS、默认 HA、版本与 appdb | `private_ha_database`（M/P） | Passed：mock plan 检查通过 |
| 非法 subnet、公网开关、Disabled HA | 三个 reject case（M/P） | Passed：非法输入按预期被拒绝 |
| 委派/DNS link、区域 SKU/HA、恢复及数据验证 | 云端授权验证 | Blocked：本变更未执行云操作 |

初始化后，在本目录执行 `terraform test`。测试仅使用明显 synthetic fixture，禁止对真实 provider 执行 apply tests。根模块已集成该模块；静态配置不能视为云端验收。

Schema 核对：2026-11-20，官方 [AzureRM v4.55.0 PostgreSQL server](https://github.com/hashicorp/terraform-provider-azurerm/blob/v4.55.0/website/docs/r/postgresql_flexible_server.html.markdown) 与 [database](https://github.com/hashicorp/terraform-provider-azurerm/blob/v4.55.0/website/docs/r/postgresql_flexible_server_database.html.markdown)。
