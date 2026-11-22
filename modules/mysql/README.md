# MySQL Flexible Server

## 配置与 ownership

仅创建私有 VNet 集成的 MySQL server、`appdb`（名称可配置）、专用 MySQL DNS zone 与 VNet link。RG、VNet、subnet 由调用方管理；**必须**提供 `subnet_ids["mysql-subnet"]`，预先委派 `Microsoft.DBforMySQL/flexibleServers`，不再退回 node subnet。此模块继续拥有原有 `privatelink.mysql.database.azure.com` zone；同一 RG 不可重复部署并接管同名 zone。不需要新增 `private_dns_zone_id` 输入，也不创建 MySQL Private Endpoint。

所有已有输入及输出名称保持不变。默认 `sku_name = "GP_Standard_D2ds_v4"`；`availability_mode` 支持 `Disabled`（省略 HA block）、`SameZone`、`ZoneRedundant`，默认 `ZoneRedundant`。HA 使用自动增长存储，禁止 Burstable SKU。MySQL 默认版本为 `8.0.21`；旧输入 `"8.0"` 映射为 `"8.0.21"`。默认 storage 为 128 GB，backup 为 7 天（模块限制 7–35 天）。`zone` 默认 `"1"`，可设 null 由 Azure 放置。

新增 `public_network_access_enabled` 为 bool，默认 false，true 被拒绝。`admin_password` 必须通过私有参数传入且 sensitive；sensitive 不避免进入 state / plan。没有密码输出、公共访问或防火墙 bypass。保留已有 server `prevent_destroy`；它不是备份或绝对防删保证。

## 状态与覆盖

M/P = mocked-provider / plan-only，不访问 Azure，不等于云端验证；测试要求 Terraform >= 1.7。父模块负责锁定 AzureRM **4.55.0** 与 random provider、认证及初始化。子模块仅声明 provider source，不配置登录。根模块目前的旧 provider 约束需要调用方另行升级，不能用本模块的静态检查证明整个仓库就绪。

| case | 配置/测试 | 结果 |
|---|---|---|
| 私有委派子网、默认 HA、storage auto-grow | `private_ha_server`（M/P） | 已实现；待执行 |
| Disabled HA、兼容旧版本输入 | `disabled_ha_legacy_version`（M/P） | 已实现；待执行 |
| 缺失 mysql-subnet 禁止 node fallback | `reject_node_subnet_fallback`（M/P） | 已实现；待执行 |
| 公网开关、错误 SKU | 两个 reject case（M/P） | 已实现；待执行 |
| 区域/SKU/版本生命周期、DNS、实际恢复 | 云端授权验证 | Blocked：本变更未执行云操作 |

初始化后，在本目录执行 `terraform test`。任何真实 plan / apply 前核对现有 state、DNS ownership、区域可用性、替换风险及已运行实验；本模块不启动故障。

Schema 核对：2026-11-20，官方 [AzureRM v4.55.0 MySQL server](https://github.com/hashicorp/terraform-provider-azurerm/blob/v4.55.0/website/docs/r/mysql_flexible_server.html.markdown) 与 [database](https://github.com/hashicorp/terraform-provider-azurerm/blob/v4.55.0/website/docs/r/mysql_flexible_database.html.markdown)。MySQL server 使用 `public_network_access = "Disabled"`，不是 PostgreSQL 的 bool 字段。
