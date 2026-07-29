# Release v3.0.0

Portkey Gateway Terraform — Azure Container Apps (ACA) and AWS ECS.

This is a **major release** with breaking changes on the Azure (ACA) side and new
capabilities on both platforms. Before upgrading, read the
**[Migration Guide → v3.0.0](./MIGRATION-v3.0.0.md)**.

> Applies to both **Clone & Deploy** and **module-based** deployments.

---

## Highlights

- **Data Service is now supported on Azure Container Apps** and configurable on both platforms.
- **Least-privilege RBAC on Azure** — scoped, per-secret Key Vault access and custom blob roles.
- **Control Plane Private Link DNS updated** to `private.azure-cp.portkey.ai`.
- **Pinned default image tags** for reproducible deployments.
- **Safer ECS operations** — opt-in ECS Exec, rolling ASG instance refresh, scoped SSM access.

---

## Breaking Changes

See the [migration guide](./MIGRATION-v3.0.0.md#breaking-changes) for full details and steps.

- **[ACA] Control Plane FQDN changed** from `azure-cp.privatelink-az.portkey.ai` to
  `private.azure-cp.portkey.ai` (DNS zone `privatelink-az.portkey.ai` → `azure-cp.portkey.ai`,
  A record `azure-cp` → `private`). Update `CONTROL_PLANE_BASEPATH`, `ALBUS_BASEPATH`,
  `SOURCE_SYNC_API_BASEPATH`, and `CONFIG_READER_PATH`.
- **[ACA] Control Plane Private Endpoint recreated** (new name `pe-controlplane-v2-*` and new
  Private Link Service alias). The connection must be **re-approved by Portkey**.
- **[ACA] RBAC tightened** — vault-wide Key Vault access and `Storage Blob Data Contributor`
  are replaced by per-secret assignments and custom blob roles. Expect role diffs on apply.
- **[ACA & ECS] Default image tags pinned** — `gateway` → `2.10.0`, `data-service` → `1.8.0`
  (previously `latest`).
- **[ECS] `enable_execute_command` now defaults to `false`** for gateway, data-service, and
  redis (previously hard-coded `true` for data-service/redis).

---

## What's New

### Azure Container Apps (ACA)

- **Data Service support** — provisioned when `dataservice_config.enable_dataservice = true`,
  running under a dedicated user-assigned identity with scoped Key Vault and blob permissions.
  Internal-only; never publicly exposed. New `dataservice_config` and `data_service_image` variables.
- **Least-privilege identities** — per-secret Key Vault `Secrets User` grants and custom
  read/write(/delete) blob role definitions replace broad built-in roles.
- **More robust Docker credential handling** — Docker username/password resolved at the root
  to avoid the azurerm "inconsistent final plan" issue for private registries.

### AWS ECS

- **Configurable Data Service port** and `enable_execute_command` via `dataservice_config`.
- **`instance_refresh` variable** — optional rolling replacement of capacity-provider
  instances on launch-template changes (disabled by default).
- **Scoped SSM Session Manager access** for container instances via an inline policy instead
  of the managed `AmazonSSMManagedInstanceCore` policy.
- **`enable_execute_command`** exposed on `gateway_config`, `dataservice_config`, and
  `redis_configuration`.
- Autoscaling module pinned to `9.2.1`.

---

## Upgrade

Follow the **[Migration Guide → v3.0.0](./MIGRATION-v3.0.0.md)**.

Quick summary:

1. Update Control Plane URLs (ACA) and any new variables (`dataservice_config`,
   `data_service_image`, `enable_execute_command`, `instance_refresh`).
2. `terraform init -upgrade && terraform plan` — review PE recreation (ACA) and RBAC/IAM diffs.
3. `terraform apply`.
4. **ACA only:** submit the new Control Plane Private Endpoint ID to Portkey and wait for approval.

---

## Compatibility

- Upgrades from **v2.x**.
- No changes required to remote state backends.
