# Azure Managed Redis

This module manages `Microsoft.Cache/redisEnterprise`, its `default` database,
explicit workload access-policy assignments, and one private endpoint. It never
starts chaos actions. Root owns the resource group, subnet, DNS zone and VNet links.
Providers are configured by the caller; baseline AzureRM 4.55.0 and root-pinned
AzAPI 2.14.0. Module constraints allow the caller's compatible 2.x version.
The ARM parent ID uses the authenticated subscription and caller-supplied resource
group name, without looking up a resource group that may still be awaiting creation.

## API verification (2026-11-20)

The previously configured **2025-04-01** cluster schema contains
`minimumTlsVersion`, `highAvailability` and encryption, but **does not contain
`publicNetworkAccess`**. The database schema includes
`accessKeysAuthentication = "Disabled"` and ARM eviction enums such as
`AllKeysLRU` (not Redis's `allkeys-lru` spelling).

The official networking guidance says APIs before **2025-07-01** were deprecated
in October 2026 and can no longer be used. This module therefore uses verified
**2025-07-01** for all three resource types, with schema validation enabled:

* `Microsoft.Cache/redisEnterprise`: `sku.name`; properties
  `minimumTlsVersion = "1.2"`, `highAvailability = "Enabled"`,
  **`publicNetworkAccess = "Disabled"`**.
* `Microsoft.Cache/redisEnterprise/databases`: `clientProtocol = "Encrypted"`,
  `clusteringPolicy = "OSSCluster"`, `evictionPolicy`, `port = 10000`,
  `persistence`, module `{name}` entries and `accessKeysAuthentication = "Disabled"`.
* `Microsoft.Cache/redisEnterprise/databases/accessPolicyAssignments` (not an
  invented `accessPolicies` child): properties
  `{ accessPolicyName = "default", user = { objectId = "<principal-object-id>" } }`.
  Only `default` is supported by this pinned stable schema. Assignment names are
  1-60 alphanumeric characters; the principal object ID is **not** its client ID.
  `default` grants full Redis command/key access; isolate this fixture and grant
  only explicitly selected workload identities. Custom limited ACLs require a
  separately verified schema change, not a guessed property.

## Contract and authentication

Existing input/output names are retained. `use_azapi = false` intentionally
disables **every resource and data read**, and all outputs become null.
When true, `subnet_id` and `private_dns_zone_id` are required; there is no public
or plaintext fallback. The actual cluster name is the lowercased,
underscore-to-hyphen normalized `env_prefix-redis_name`.
**Migration warning:** an existing deployment whose actual name omitted the
prefix can be replaced by this correction; review the saved plan and ownership
before applying. Never remove state to disguise replacement.

The legacy primary/secondary key output names remain **always null** because
key authentication is explicitly disabled, not because lookup failed. No
`listKeys` request is made. Consumers must migrate to Entra instead of using
these compatibility outputs.

Supply `access_policy_assignments = { workload = "<principal-object-id>" }`.
An empty map authorizes **no SDK workload identity**: business tests are
**Blocked / 阻塞** until an explicit assignment is provided. Workload identity
federation/OIDC and the AKS service account remain caller-owned. SDKs must obtain
`https://redis.azure.com/.default` tokens, authenticate with principal object ID
as username, and refresh/re-AUTH before expiry. This is not anonymous access.
Changing key authentication on an existing database disconnects clients;
review and authorize the transition separately.

## DNS

Managed Redis's exact private zone is **`privatelink.redis.azure.net`**;
the endpoint group ID is **`redisEnterprise`**. Root owns that zone and its VNet
links. This differs from legacy `privatelink.redis.cache.windows.net` and
Enterprise-tier `privatelink.redisenterprise.cache.azure.net`.

SDKs connect to `<cache>.<region>.redis.azure.net:10000` using TLS, not the
private-link alias. Confirm the hostname resolves privately from cloud AKS.

## A/R coverage and blockers

* **A / availability:** sustained cloud AKS requests through the private endpoint,
  bounded client retry/reconnection and token refresh; verify readiness,
  latency and success-rate baselines before authorized fault runs.
* **R / recovery:** verify acknowledged test keys after recovery, reconciliation
  and recovery time. AOF/RDB persistence are disabled in this fixture, so Redis
  is not a durable source of truth; test-data loss is a measured risk, not a pass.
* Legacy Redis reboot targets `Microsoft.Cache/redis`, **not this Managed Redis
  resource**. No equivalent Managed Redis chaos action is implied. Action,
  region/SKU support, authorization, stopping thresholds and cloud business
  evidence are **Blocked / 阻塞** until separately verified.

Mocked plan tests cover disabled indexing and TLS/plaintext rejection. They
do not establish cloud provisioning, DNS, RBAC propagation or resilience.
No cloud runs are part of this change.

Official references:

* [2025-04-01 cluster schema](https://learn.microsoft.com/en-us/azure/templates/microsoft.cache/2025-04-01/redisenterprise)
* [2025-07-01 cluster schema](https://learn.microsoft.com/en-us/azure/templates/microsoft.cache/2025-07-01/redisenterprise)
* [Database schema](https://learn.microsoft.com/en-us/azure/templates/microsoft.cache/2025-07-01/redisenterprise/databases)
* [Assignment schema](https://learn.microsoft.com/en-us/azure/templates/microsoft.cache/2025-07-01/redisenterprise/databases/accesspolicyassignments)
* [Private Link and API retirement](https://learn.microsoft.com/en-us/azure/redis/private-link)
* [Exact private DNS zones](https://learn.microsoft.com/en-us/azure/private-link/private-endpoint-dns)
* [Entra client authentication](https://learn.microsoft.com/en-us/azure/redis/entra-for-authentication)
