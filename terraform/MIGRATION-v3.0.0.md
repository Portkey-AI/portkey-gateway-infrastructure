# Migration Guide — v2.x → v3.0.0

This guide covers upgrading the Portkey Gateway Terraform deployments to **v3.0.0** for both platforms:

- **Azure Container Apps (ACA)** — `terraform/aca`
- **AWS ECS** — `terraform/ecs`

It applies to both **Clone & Deploy** (you edit `environments/<env>/*`) and **Module-based** (you consume the module from your own root config) styles.

> **v3.0.0 contains breaking changes.** The important one is the ACA Control Plane Private Link recreation — follow the [Safe Migration](#safe-migration--control-plane-private-link-aca) steps to avoid an outage.

---

## Breaking Changes

| # | Platform | Change | Action required |
|---|----------|--------|-----------------|
| 1 | ACA | Control Plane Private Endpoint **recreated** (new name + new PLS alias) and **DNS zone/FQDN changed** | Follow [Safe Migration](#safe-migration--control-plane-private-link-aca); re-approve the new PE; update Control Plane URLs |
| 2 | ACA | **Least-privilege RBAC** replaces vault-wide / broad blob roles | Re-apply; identity must be able to create custom roles + role assignments |
| 3 | ACA & ECS | Default image tags **pinned** (`gateway` → `2.16.0`, `data-service` → `1.9.0`) | Confirm or set your own tags |
| 4 | ACA | **Data Service** now supported (was hard-disabled) | Opt in via `dataservice_config` if desired |
| 5 | ECS | `dataservice_config.port` + `enable_execute_command` now configurable; SSM via scoped policy; ASG `instance_refresh` added | Set `enable_execute_command = true` where you rely on ECS Exec |

Non-breaking additions are in the [release notes](./RELEASE_NOTES-v3.0.0.md).

---

## Safe Migration — Control Plane Private Link (ACA)

**Applies only if** you use outbound Private Link (`control_plane_private_link.outbound = true`).

In v3.0.0 the Private Endpoint and DNS change:

| | v2.x | v3.0.0 |
|---|------|--------|
| Private Endpoint | `pe-controlplane-*` | `pe-controlplane-v2-*` |
| PLS alias | old | new |
| Private DNS Zone | `privatelink-az.portkey.ai` | `azure-cp.portkey.ai` |
| **Control Plane FQDN** | `azure-cp.privatelink-az.portkey.ai` | `private.azure-cp.portkey.ai` |

A straight `terraform apply` would **destroy the old Private Endpoint before the new one is approved**, cutting off the Control Plane until Portkey approves the new connection.

To avoid that, **remove the old Private Link resources from state first** so Terraform stops managing them (they keep running in Azure). Because the new resources have different names/zone, both sets coexist during the cutover.

### Steps

**1. Back up state.**

```bash
terraform state pull > backup-$(date +%Y%m%d-%H%M%S).tfstate
```

**2. Find the exact resource addresses.**

```bash
terraform state list | grep control_plane
```

**3. Remove the old Private Link resources from state** (they will NOT be deleted from Azure):

```bash
terraform state rm 'azurerm_private_endpoint.control_plane[0]'
terraform state rm 'azurerm_private_dns_zone.control_plane[0]'
terraform state rm 'azurerm_private_dns_zone_virtual_network_link.control_plane[0]'
terraform state rm 'azurerm_private_dns_a_record.control_plane[0]'
```

> Module-based: prefix each address with your module name, e.g. `module.portkey_gateway.azurerm_private_endpoint.control_plane[0]`. Use the exact addresses from step 2.

**4. Plan and verify — this is the safety check.** Confirm the plan only **creates** the new Private Link resources and does **not** destroy/replace anything. There should be **no `destroy` and no `replace` (`-/+`)** actions on the Private Endpoint, DNS zone, vnet link, or A record.

```bash
terraform plan -var-file=environments/<env>/<env>.tfvars
```

Expected: the four `control_plane` resources show as `+ create` (4 to add), with `0 to destroy`. If you see any `-` (destroy) or `-/+` (replace) on these resources, **stop** — an address was missed in step 3. Re-check `terraform state list | grep control_plane` and remove the remaining old resource before continuing.

**5. Apply.** Terraform creates the new PE (`pe-controlplane-v2-*`), the new zone `azure-cp.portkey.ai`, and the `private` A record. The old PE keeps serving traffic.

```bash
terraform apply -var-file=environments/<env>/<env>.tfvars
```

**6. Get the new PE ID and send it to Portkey for approval.**

```bash
terraform output -raw control_plane_private_endpoint_id
# Poll until Approved:
az network private-endpoint show \
  --ids $(terraform output -raw control_plane_private_endpoint_id) \
  --query 'privateLinkServiceConnections[0].privateLinkServiceConnectionState.status' -o tsv
```

**7. Cut over the Control Plane URLs** to the new FQDN, then redeploy the gateway.

Clone & Deploy — edit `environments/<env>/environment-variables.json`:

```json
{
  "gateway": {
    "ALBUS_BASEPATH": "https://private.azure-cp.portkey.ai/albus",
    "CONTROL_PLANE_BASEPATH": "https://private.azure-cp.portkey.ai/api/v1",
    "SOURCE_SYNC_API_BASEPATH": "https://private.azure-cp.portkey.ai/api/v1/sync",
    "CONFIG_READER_PATH": "https://private.azure-cp.portkey.ai/api/model-configs"
  }
}
```

Module-based — update the same keys in your `environment_variables.gateway` map.

**8. Validate** from inside the VNET (should succeed with full cert verification):

```bash
wget -qO- https://private.azure-cp.portkey.ai/albus/health
```

**9. Clean up the old resources** once traffic is confirmed on the new endpoint. Delete the orphaned v2.x resources in Azure (they are no longer in state):

- Private Endpoint `pe-controlplane-*`
- Private DNS Zone `privatelink-az.portkey.ai` (with its vnet link + `azure-cp` A record)

---

## Other ACA Changes

- **Least-privilege RBAC (#2):** Key Vault access is now granted per-secret, and the gateway uses a custom blob role (read/write/append, no delete) instead of `Storage Blob Data Contributor`. Data Service runs under its own identity with scoped roles. No variable changes, but the applying identity must be able to create custom role definitions and role assignments; expect an IAM diff.
- **Data Service (#4):** opt in via `dataservice_config = { enable_dataservice = true }` and `data_service_image = { image = "portkeyai/data-service", tag = "1.9.0" }`. Internal-only; defaults to disabled.

## Other ECS Changes

- `dataservice_config` gained `port` (default `8081`, now used by health check + service connect) and `enable_execute_command` (default `false`).
- `enable_execute_command` is now opt-in on `gateway_config`, `dataservice_config`, and `redis_configuration` — set `true` where you use `aws ecs execute-command`.
- SSM access uses a scoped inline policy instead of the managed `AmazonSSMManagedInstanceCore`; new optional `instance_refresh` block; autoscaling module pinned to `9.2.1`. No action required beyond reviewing the IAM diff.

## Image Tag Pinning (both platforms)

Defaults are pinned. If your `*.tfvars` still uses `latest`, set explicit tags:

```hcl
gateway_image      = { image = "portkeyai/gateway_enterprise", tag = "2.16.0" }
data_service_image = { image = "portkeyai/data-service",        tag = "1.9.0" }
```

---

## Upgrade Steps

1. Pull the v3.0.0 tag/branch (Clone & Deploy) or bump the module `source` ref (Module-based).
2. **ACA with Private Link:** follow [Safe Migration](#safe-migration--control-plane-private-link-aca) — do the `state rm` before applying.
3. Apply the other platform changes above to your `*.tfvars` / `environment-variables.json`.
4. Plan and review (expect PE creation on ACA and RBAC/IAM diffs):

```bash
terraform init -upgrade
terraform plan -var-file=environments/<env>/<env>.tfvars
```

5. `terraform apply`.
6. **ACA only:** submit the new Control Plane PE ID to Portkey, wait for approval, then cut over URLs and validate.

---

## Rollback

- **ECS:** revert the module ref / tfvars to v2.x and re-apply. No destructive data changes.
- **ACA:** if you followed the safe migration and kept the old resources, roll back by restoring the previous Control Plane URLs (`azure-cp.privatelink-az.portkey.ai`) and redeploying the gateway — the old Private Endpoint is still live. Remove the new v3 resources afterward.

---

## Support

- Open an issue in the GitHub repository.
- Contact the Portkey support team (needed for Control Plane Private Endpoint approvals).
