# VM module

Azure-only module; provider versions are selected by the caller. `vms` remains a
stable-key map. Each entry requires `vm_name`, `vm_size`, `subnet_name`,
`admin_username`, and the original `ssh_public_key_path` input (nonempty for Linux).
`image_version` retains its optional `latest` compatibility default; numeric
versions are validated when supplied. The hardened root profile supplies a pinned
version separately. `ssh_private_key_path` is additive and optional: when omitted,
connection instructions use operator-configured SSH authentication and never
invent a private key path. Only the public key is read. Verify the image's
publisher/offer/SKU/version availability in the target region before deployment.
Windows images must override the Linux image defaults.

Public IP creation defaults to false. Connection outputs use the private IP when
no public IP exists; private network reachability is an operator prerequisite.
`vm_ids` includes Linux and Windows. Windows credentials are generated in state
but never output; use a protected remote backend and an approved credential
delivery/rotation mechanism. No NSG access rule is added implicitly.

`attach_nsg` defaults to true for clean deployments. Setting it to false retains
the NSG definition/resource but omits the NIC association; it does not import or
modify company-policy NSGs. The dev profile preserves its original rule templates
and leaves those associations disabled. A public jumpserver separately uses
`protect_public_ssh`: its dedicated access NSG allows only the approved
`public_ssh_source_cidrs` to TCP 22 and denies other inbound traffic. An empty list
is deny-only and explicitly outputs SSH status `Blocked`. The access NSG is
attached before VM provisioning even when original-template attachment is off.
Generic caller behavior is unchanged unless this protection is explicitly opted
in. Review effective subnet/company policy before business tests.

The original nonempty Linux `custom_script` input continues to create its
CustomScript extension at the existing resource address. An empty script creates
no extension. Scripts execute during an explicitly authorized deployment, not
during editing or validation; their safety, pinning, secrets and rollback must be
reviewed independently. Extension provisioning is not application readiness.

## RocketMQ bootstrap

`bootstrap_rocketmq = true` adds cloud-init only to the selected private Linux VM.
It requires a pinned Canonical Ubuntu 22.04 Gen2 image and rejects a competing
`custom_script`. The [installer](scripts/rocketmq-bootstrap.sh) pins Apache 5.5.1
and its official SHA512, verifies downloads, uses signed Ubuntu JRE17 packages,
and runs dedicated-user `rocketmq-nameserver` / `rocketmq-broker` systemd services.
No Docker socket, public endpoint, console, or Chaos fault is configured.
Store data is under `/var/lib/rocketmq/store` with synchronous flush; a single
broker is not an HA cluster and deleting its disk loses stored messages.

Installation requires outbound access. Cloud-init runs after VM provisioning:
check `cloud-init status --wait`, both services, broker registration, and cloud
AKS message send/read before claiming readiness. The offline mocked installer
tests check repeat runs and failure paths, not Azure connectivity or business
recovery. Public SSH key paths support `~` expansion; private keys are never read.
Original NSG rule inputs remain unchanged.

## Migration impact

Resource addresses and existing map inputs are preserved, including Linux
CustomScript. Default public IP creation changes from true to false: existing
entries that omitted the flag must explicitly set `enable_public_ip=true` to
retain their public IP during migration, or review the proposed IP deletion and
private-access replacement. Changing an explicitly pinned image can replace VMs.
Windows generated passwords now guarantee lowercase/uppercase/numeric classes;
existing random-password resources may rotate and update VM credentials when
these constraints are introduced. Review that plan and coordinate credential
delivery before applying.
No state migration is executed.

`vm_ids` now includes Windows; private jumpserver/RocketMQ connection outputs no
longer silently return null. `rocketmq_details` no longer asserts unverified
service endpoints or a plaintext public console URL: consumers of
`nameserver_endpoint`, `broker_endpoint`, `broker_ha_endpoint` and `console_url`
must migrate to separately verified application service discovery. Connection
output names remain unchanged. Windows SSH outputs are null instead of an N/A
string; no password is output. NSG/NIC-association address changes, if present,
require a reviewed moved/import mapping rather than blind recreation.

`terraform test` uses mocked providers only; its fixture key is not a deployment
credential. Tests do not establish Azure image availability or application health.
