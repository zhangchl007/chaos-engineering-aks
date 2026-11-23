# Blob private fixture

Caller-configured AzureRM **4.55.0**. Required inputs: `name` (caller produces
a globally unique 3-24 lowercase-alphanumeric name), `resource_group_name`,
`location`, `subnet_id`, `private_dns_zone_id`. The caller owns the non-delegated
endpoint subnet, `privatelink.blob.core.windows.net` zone and workload VNet links.
This module only associates the existing zone via a private DNS zone group.
Confirm actual subnet delegation and region/replication support before approval.

Optional inputs: `tags = {}`, `replication_type = "ZRS"` (allowed: LRS, ZRS,
GRS, RAGRS, GZRS, RAGZRS), `soft_delete_retention_days = 7` (1-365), and
`workload_principal_ids = {}` (stable keys to Entra principal object IDs).
The latter grants Storage Blob Data Contributor **only on test-data**, not on
the storage account or subscription; empty map creates no grants.

Creates Standard StorageV2 with **Blob-only fixture connectivity**, the private
`test-data` container, Blob versioning, Blob/container soft delete, HTTPS/TLS1.2,
no public network/anonymous/shared-key access. StorageV2's account supports other
services but this module does not provision Queue/Table/File fixtures or endpoints.
Outputs: `storage_account_id`, sensitive `blob_endpoint`, `container_name`.
The sensitive marker limits display only; state/plan remain protected assets.

`azurerm_storage_container.storage_account_id` selects Azure Resource Manager
container creation in 4.55.0 instead of the deprecated shared-key/data-plane path.
Do not switch to `storage_account_name` or update access levels on existing
containers without reviewing provider shared-key caveats.
The root provider must set **`storage_use_azuread = true`**. Blob properties and
refresh can still need data-plane access: the authorized Terraform runner needs
private DNS/network reachability and appropriate pre-existing Blob data-plane
RBAC (not just control-plane Contributor). RBAC ordering does not guarantee
propagation. Do not enable public/shared-key access as a workaround.

## Service case: B (Blob)

An authorized cloud AKS workload-identity Job writes bounded correlated blobs,
reads and hashes acknowledged content, tests only explicitly approved overwrite/
delete cases, and verifies retained versions and recovery of confirmed data.
Record success rate, latency, retries and recovery time through any independently
approved disruption; stop does not mean data/business recovery is complete.
Soft-delete/versioning increases storage costs and is not an immutable backup.

ZRS is **in-region** redundancy, not cross-region DR. Geo-redundant settings alone
do not validate RPO/RTO or client recovery. Secondary-region access/private DNS,
object replication, backups, account failover/failback and restore drills require
**later explicit configuration and approval**. Protection settings do not execute
protection/DR operations. No fault, deletion, failover or restore is auto-started.

## Validation / blockers

Mock/plan tests in `tests/` need Terraform >= 1.7 and the pinned provider.
The coordinator initializes/validates; root, state and shared networking remain
outside this change. **Blocked：云端读写、版本/软删除恢复及 DR 尚无执行证据；
不能以静态配置或 mock 测试判为 Passed。**

Pinned official schemas verified 2026-11-20:
[account](https://github.com/hashicorp/terraform-provider-azurerm/blob/v4.55.0/website/docs/r/storage_account.html.markdown),
[ARM container](https://github.com/hashicorp/terraform-provider-azurerm/blob/v4.55.0/website/docs/r/storage_container.html.markdown),
[private endpoint](https://github.com/hashicorp/terraform-provider-azurerm/blob/v4.55.0/website/docs/r/private_endpoint.html.markdown).
