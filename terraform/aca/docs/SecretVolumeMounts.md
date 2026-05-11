# Mounting Key Vault Secrets as Files

Project Key Vault secrets as files on **gateway** and **mcp** using **`gateway_secret_volume_mounts`**.

Every secret must appear in **`secrets.gateway`** (Terraform) or the **`gateway`** object in **`secrets.json`**. The module registers each as a Container App secret (Key Vault reference) and **also** as a **secret environment variable**. Then `gateway_secret_volume_mounts` defines where those secrets appear as files.

## 1. Key Vault secret

Secret names may only use letters, numbers, and hyphens (no dots). Example: `llm-server-ca`.

```bash
az keyvault secret set --vault-name <your-vault> --name llm-server-ca --file ./ca.pem
```

## 2. Terraform

```hcl
secrets = {
  gateway = {
    LLM_SERVER_CA = "llm-server-ca"
  }
}

gateway_secret_volume_mounts = [
  {
    name       = "llm-server-ca"
    mount_path = "/etc/ssl/certs/llm-server-ca.pem"
    sub_path   = "llm-server-ca"
  }
]

environment_variables = {
  gateway = {
    NODE_EXTRA_CA_CERTS = "/etc/ssl/certs/llm-server-ca.pem"
  }
}
```

- `sub_path` must be the Key Vault secret name, not a dotted filename.
- `mount_path` can include `.pem` even though the Key Vault name cannot.

