# Copy to an ignored *.private.tfvars and choose approved values before planning.
subscription_id    = "00000000-0000-0000-0000-000000000000"
tenant_id          = "00000000-0000-0000-0000-000000000000"
environment        = "test"
env_prefix         = "example-test"
location           = "westus2"
kubernetes_version = "1.36.0" # Example only; verify region and patch eligibility.
use_existing_acr   = false

components = {
  mysql       = true
  postgresql  = true
  cosmosdb    = true
  redis       = true
  azure_cache = false # Enable only after confirming the target tenant's creation eligibility.
  eventhub    = true
  servicebus  = true
  storage     = true
  vm          = false # Supply an approved explicit VM map and pinned image first.
}

storage_account_name = "replacewithuniquename"
# Supply database bootstrap credentials privately, never commit them here.
# New classic Azure Cache is separate from Managed Redis and remains opt-in.
# Existing legacy references remain read-only and cannot be combined with new creation.
