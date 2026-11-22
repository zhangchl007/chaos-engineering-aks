# AKS and Azure Chaos Terraform fixtures

This repository prepares isolated non-production infrastructure and declarative Chaos Studio configuration. **Creating configuration never starts a fault. Nothing has been deployed or run by this implementation.**

Read the [coverage review and implementation status](./docs/terraform-chaos-coverage-plan.md), [deployment and migration runbook](./docs/terraform-deployment-runbook.md) and [PaaS test draft](./docs/paas-chaos-test-plan.md) first. Existing environments must not adopt the changed configuration without a separately reviewed migration plan.

## Stages and ownership

| Stage | Owns |
| --- | --- |
| [Bootstrap](./stacks/bootstrap/) | Independent protected private state storage, access and DNS |
| [Repository root](./main.tf) | Single platform RG, private network/AKS/ACR, optional data/VM/AGFC fixtures, bounded monitoring |
| [Cluster](./stacks/cluster/) | Controller/GitOps profiles and opt-in restricted verification Jobs on an existing private AKS |
| [Chaos](./stacks/chaos/) | Disabled-by-default Workspace, runtime identity, scoped permissions and bounded Scenarios/configurations |

Keep a distinct local state path or remote backend Blob key, and appropriately scoped identity, for every stage/environment. A tfvars switch or CLI workspace name does not provide state/security isolation. The initial bootstrap state is local and sensitive; back it up and protect it independently.

The platform root defaults to a **local backend** at `local-state/dev/platform.tfstate`; it needs no storage account or storage access key. Run `terraform init -input=false -lockfile=readonly` without the old Azure backend config. The [optional local backend example](./environments/dev-platform.backend.hcl.example) can override the path. Azure Storage is opt-in through the [enablement steps](./docs/terraform-deployment-runbook.md#optional-remote-state) and [Entra-authenticated config example](./environments/dev-platform.azurerm.backend.hcl.example). Use separate paths for other environments, restrict local file permissions, and keep private backups. Do not run from multiple machines against separate copies of the same environment's state. Existing state must be preserved; backend migration requires separate approval. Cluster and Chaos also default to independent local states.

## Inputs and compatibility

Use [the redacted expanded-profile example](./environments/full.example.tfvars) as input guidance, not deployment eligibility evidence. Supply subscription/tenant, a regionally supported Kubernetes patch, private runner connectivity, ownership decisions, eligible SKUs and sensitive credentials separately. Do not commit private tfvars, credentials, state or plans.

The [dev profile](./environments/dev-variables.tfvars) enables six PaaS fixtures and defers Cosmos account provisioning (`components.cosmosdb = false`). It retains the already-created Cosmos DNS/link and naming resources with `retain_cosmos_network = true`; fresh environments default this retention switch to false. Azure CNI retains a delegated pod subnet (not Azure CNI Overlay). Its Kubernetes service range is separate from the VNet; verify it against any networks connected to your deployment. `subscription_id` and `tenant_id` are optional: the providers use the authenticated Azure context, including `ARM_*` authentication settings or the current Azure CLI login. For CLI use, confirm the intended account with `az account show` and select the intended subscription with `az account set` before planning. Explicit input values override the context. Enabled MySQL/PostgreSQL fixtures generate separate 32-character passwords when their password inputs are null or empty. Optional explicit `mysql_admin_password` and `postgresql_admin_password` values take precedence; inject them privately for existing databases to avoid an unintended password change. Generated passwords are retained in Terraform state, not committed configuration. The profile references an existing ACR without creating a registry or private endpoint for it. Verify the deployment identity can read the registry and grant pull access, and that AKS can reach the registry's existing endpoint. Confirm database SKU and zone choices before planning.

After an approved apply, display the passwords explicitly in a private terminal:

```bash
terraform output -raw mysql_admin_password
terraform output -raw postgresql_admin_password
```

These outputs are marked `sensitive` so normal plan/apply logs mask them. `-raw` deliberately prints plaintext; do not run it in recorded CI logs or share its output. Generated values are not available until apply, and disabled databases have no password output. Protect state/backups and preserve the existing credential configuration; switching between generated and explicit values can rotate passwords.

The reviewed baseline is Terraform CLI **1.15.6**, AzureRM **4.55.0**, AzAPI **2.14.0**, Random **3.7.2**; the cluster stage pins Helm **2.17.0** and Kubernetes provider **2.38.0**. The AzureRM major upgrade and state/interface changes require their own migration review. Existing module input contracts were retained where possible; this is not a drop-in upgrade.

Root defaults keep extra fixtures off. The dev profile enables the existing PaaS, a separate private Azure Cache for Redis, a public-IP jumpserver, and a private RocketMQ VM with pinned images. Original NSG templates remain unchanged and unattached; jumpserver uses a separate SSH access NSG with approved management CIDRs (deny-only when absent). New classic-cache creation requires tenant eligibility confirmation and uses a dedicated AKS workload identity; existing legacy references remain read-only. RocketMQ cloud-init installs a checksum-pinned native runtime, not a fault. Cloud business readiness and idempotent replan must be verified after an authorized apply. AGFC public frontend, retired ingress/chart profiles, destructive configuration and verification Job execution each have separate opt-ins. Private AKS extension support is **Blocked**, not silently bypassed using a public cluster or classic Chaos Mesh.

## Local configuration checks

These checks do not authenticate to a deployment backend or prove cloud readiness:

```bash
terraform fmt -check -recursive
terraform init -backend=false -input=false -lockfile=readonly
terraform validate
terraform test
python3 -m unittest discover -s modules/chaos-validation/tests -p 'test_*.py'
```

Run stage/module checks independently with the reviewed provider baseline. [CI](./.github/workflows/terraform-validation.yml) uses fixed tools, backend-disabled initialization and mocked tests only; it contains no apply, destroy, fault-start, or Azure deployment credentials.

Review all policy findings rather than suppressing them globally. Full cloud plans, extension/agent installation parity, protocol-aware application ledgers, alert/stop thresholds and recovery proof remain separate gates. The built-in HTTP verifier reports availability only, never full business resilience.
