# Private Connectivity

Enable private network connectivity between your Gateway (Data Plane) and Portkey Control Plane.

## Overview

Two types of private connectivity:

- **Outbound**: Data Plane → Control Plane (your gateway connects TO Portkey)
- **Inbound**: Control Plane → Data Plane (Portkey connects TO your gateway)

---

## Outbound: Data Plane to Control Plane

Connect your Gateway to Portkey Control Plane privately over Azure Private Link.

**Prerequisites:**
- VNET deployment (`network_mode = "new"` or `"existing"`)

### Step 1: Request Whitelisting

**You do:** Share with Portkey team:
- Azure Subscription ID

**Wait for:** Portkey confirmation that your subscription is whitelisted.

---

### Step 2: Deploy Private Endpoint

**You do:** Enable outbound Private Link in your configuration.

Add to your tfvars:

```hcl
control_plane_private_link = {
  outbound = true
}
```

Deploy:

```bash
terraform apply -var-file=environments/dev/dev.tfvars
```

**What gets created:**
- Private Endpoint in your VNET
- Private DNS Zone (`privatelink-az.portkey.ai`)
- DNS A record (`azure-cp`) pointing to the Private Endpoint IP
- VNET link for DNS resolution

---

### Step 3: Request Connection Approval

**You do:** Get the Private Endpoint resource ID and share with Portkey.

```bash
terraform output control_plane_private_endpoint_id
```

**Share with Portkey team:**
- Private Endpoint resource ID

**Wait for:** Portkey to approve the connection request.

**Verify approval:**

```bash
az network private-endpoint show \
  --ids $(terraform output -raw control_plane_private_endpoint_id) \
  --query 'privateLinkServiceConnections[0].privateLinkServiceConnectionState.status' -o tsv

# Should return: "Approved"
```

---

### Step 4: Configure Private Endpoint URLs

**You do:** Update your Gateway configuration to use the private Control Plane endpoint.

**For clone & deploy:** Edit `environments/dev/environment-variables.json`:

```json
{
  "gateway": {
    "ALBUS_BASEPATH": "https://azure-cp.privatelink-az.portkey.ai/albus",
    "CONTROL_PLANE_BASEPATH": "https://azure-cp.privatelink-az.portkey.ai/api/v1",
    "SOURCE_SYNC_API_BASEPATH": "https://azure-cp.privatelink-az.portkey.ai/api/v1/sync",
    "CONFIG_READER_PATH": "https://azure-cp.privatelink-az.portkey.ai/api/model-configs"
    ...rest of env variables
  }
}
```

**For module deployment:** Update in `main.tf`:

```hcl
environment_variables = {
  gateway = {
    ALBUS_BASEPATH            = "https://azure-cp.privatelink-az.portkey.ai/albus"
    CONTROL_PLANE_BASEPATH    = "https://azure-cp.privatelink-az.portkey.ai/api/v1"
    SOURCE_SYNC_API_BASEPATH  = "https://azure-cp.privatelink-az.portkey.ai/api/v1/sync"
    CONFIG_READER_PATH        = "https://azure-cp.privatelink-az.portkey.ai/api/model-configs"
    ...rest of env variables
  }
}
```

---

### Step 5: Redeploy

**You do:** Apply the configuration changes.

```bash
terraform apply -var-file=environments/dev/dev.tfvars
```

**Done!** Your Gateway now connects to Portkey Control Plane privately.

---

## Inbound: Control Plane to Data Plane

Allow Portkey Control Plane to connect to your Gateway privately via Azure Private Endpoint.

**Prerequisites:**
- Gateway deployed and running
- No additional Terraform configuration needed (ACA supports native Private Endpoints)

---

### Step 1: Share Connection Details

**You do:** Get your Gateway connection information and share with Portkey.

```bash
# Get ACA Environment Resource ID
terraform output container_app_environment_id

# Get Gateway FQDN
terraform output inbound_gateway_fqdn

```

**Share with Portkey team:**
1. **ACA Environment Resource ID**
   ```
   /subscriptions/xxx/resourceGroups/xxx/providers/Microsoft.App/managedEnvironments/xxx
   ```

2. **Gateway FQDN**
   ```
   gateway.<env-domain>.<region>.azurecontainerapps.io
   ```
---

### Step 2: Wait for Connection Request

**Portkey does:** Creates a Private Endpoint in their subscription targeting your ACA Environment.

**Wait for:** Connection request to appear in your Azure subscription.

**Check for requests:**

```bash
# List all pending/approved connections
az network private-endpoint-connection list \
  --id $(terraform output -raw container_app_environment_id) \
  --type Microsoft.App/managedEnvironments \
  --query "[].{Name:name, Status:properties.privateLinkServiceConnectionState.status, Description:properties.privateLinkServiceConnectionState.description}"
```

---

### Step 3: Approve Connection

**You do:** Approve the incoming Private Endpoint connection request.

```bash
# Approve the connection
az network private-endpoint-connection approve \
  --id "<connection-id-from-step-2>" \
  --description "Approved for Portkey Control Plane"

# Verify approval
az network private-endpoint-connection show \
  --id "<connection-id>" \
  --query "properties.privateLinkServiceConnectionState.status"

# Should return: "Approved"
```

**Done!** Portkey Control Plane can now reach your Gateway privately.

---
