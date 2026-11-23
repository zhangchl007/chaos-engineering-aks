# Copy to a private file and replace every placeholder before planning.
subscription_id   = "<deployment-subscription-id>"
tenant_id         = "<deployment-tenant-id>"
resource_group_id = "<existing-workspace-resource-group-id>"
location          = "<approved-supported-workspace-region>"
name              = "<unique-dev-workspace-name>"

# Creates the Workspace, identity and Reader discovery grant, not a fault run.
enabled = true
scopes  = ["<approved-dev-resource-group-id>"]

# Add exact targets and validated permissions only after Workspace onboarding.
scenarios                       = {}
permissions                     = {}
aks_extensions                  = {}
pod_scenarios                   = {}
excluded_resource_ids           = []
allow_destructive_configuration = false
