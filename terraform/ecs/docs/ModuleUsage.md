# Module-Based Deployment

Use the Portkey Gateway Terraform module to deploy infrastructure as code in your own Terraform project. This approach is recommended for production deployments, multi-environment management, and version-controlled upgrades.

## Table of Contents

- [Prerequisites](#prerequisites)
- [Quick Start](#quick-start)
- [Project Structure](#project-structure)
- [Backend Configuration](#backend-configuration)
- [Module Configuration](#module-configuration)
- [Complete Examples](#complete-examples)
- [Configuration Guides](#configuration-guides)
- [Multi-Environment Setup](#multi-environment-setup)
- [Version Pinning](#version-pinning)
- [Upgrading](#upgrading)

## Prerequisites

| Requirement | Details |
|-------------|---------|
| **Portkey Account** | Sign up at [portkey.ai](https://portkey.ai) |
| **AWS Account** | With permissions for ECS, EC2, VPC, ELB, IAM, S3, Secrets Manager, CloudWatch |
| **Terraform** | v1.13+ ([installation](https://developer.hashicorp.com/terraform/install)) |
| **AWS CLI** | Configured with credentials ([installation](https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html)) |

## Quick Start

### 1. Prepare AWS Secrets

Use the CloudFormation template to create secrets in AWS Secrets Manager:

1. Go to the [AWS CloudFormation Console](https://console.aws.amazon.com/cloudformation) and create a stack.
2. Upload `cloudformation/secrets.yaml` from the [portkey-gateway-infrastructure](https://github.com/Portkey-AI/portkey-gateway-infrastructure) repository.
3. Provide:
   - **Project Name** — e.g., `portkey-gateway`
   - **Environment** — e.g., `dev`
   - **Docker Username / Password** — provided by Portkey
   - **Portkey Client Auth** — provided by Portkey
   - **Organizations** — your Portkey organisation ID(s), comma-separated if multiple
4. After the stack completes, note the outputs:
   - `DockerCredentialsSecretArn`
   - `ClientOrgSecretNameArn`

Alternatively, create secrets manually:

```bash
aws secretsmanager create-secret \
  --name portkey-gateway/dev/docker-credentials \
  --secret-string '{"username":"<docker-username>","password":"<docker-password>"}'

aws secretsmanager create-secret \
  --name portkey-gateway/dev/client-org \
  --secret-string '{"PORTKEY_CLIENT_AUTH":"<client-auth>","ORGANISATIONS_TO_SYNC":"<organisation-id>"}'
```

### 2. Create Your Terraform Project

```bash
mkdir portkey-gateway-deployment
cd portkey-gateway-deployment
```

Create `main.tf`:

```hcl
terraform {
  required_version = ">= 1.13"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }

  backend "s3" {}
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Environment = var.environment
      ManagedBy   = "Terraform"
      Project     = var.project_name
    }
  }
}

# Replace vX.Y.Z with the desired module version (e.g., v1.0.0)
module "portkey_gateway" {
  source = "github.com/Portkey-AI/portkey-gateway-infrastructure//terraform/ecs?ref=vX.Y.Z"

  project_name = "portkey-gateway"
  environment  = "dev"
  aws_region   = "us-east-1"

  docker_cred_secret_arn = "<DockerCredentialsSecretArn>"

  environment_variables = {
    gateway = {
      SERVICE_NAME    = "gateway"
      ANALYTICS_STORE = "control_plane"
      LOG_STORE       = "s3_assume"
    }
  }

  secrets = {
    gateway = {
      PORTKEY_CLIENT_AUTH   = "<ClientOrgSecretNameArn>"
      ORGANISATIONS_TO_SYNC = "<ClientOrgSecretNameArn>"
    }
  }

  # Network
  create_new_vpc     = true
  vpc_cidr           = "10.0.0.0/16"
  num_az             = 2
  single_nat_gateway = true

  # Cluster
  create_cluster   = true
  instance_type    = "t4g.medium"
  min_asg_size     = 1
  max_asg_size     = 2
  desired_asg_size = 1

  # Gateway
  gateway_config = {
    desired_task_count = 1
    cpu                = 256
    memory             = 1024
    gateway_port       = 8787
    mcp_port           = 8788
  }

  server_mode = "gateway"

  # Redis (built-in)
  redis_configuration = {
    redis_type = "redis"
    cpu        = 256
    memory     = 512
    endpoint   = ""
    tls        = false
    mode       = "standalone"
  }

  # Log store
  object_storage = {
    log_store_bucket = "<your-logs-bucket>"
    bucket_region    = "us-east-1"
  }

  # Load balancer (optional)
  create_lb   = false
  internal_lb = true
  lb_type     = "network"
}

output "load_balancer_dns_name" {
  value = module.portkey_gateway.load_balancer_dns_name
}

output "vpc_id" {
  value = module.portkey_gateway.vpc_id
}
```

### 3. Deploy

```bash
terraform init -backend-config=backend.config
terraform plan
terraform apply
```

### 4. Verify

```bash
# If a load balancer was created
curl "http://$(terraform output -raw load_balancer_dns_name)/v1/health"

# Or test via ECS task networking / port-forward if create_lb = false
```

## Project Structure

Your Terraform project directory:

```
portkey-gateway-deployment/
├── main.tf              # Module + backend configuration
├── variables.tf         # (optional) Your own variables
├── terraform.tfvars     # (optional) Variable values
├── outputs.tf           # (optional) Additional outputs
├── backend.config       # (optional) Backend config file
└── config/              # (optional) JSON files if using file-based config
    ├── environment-variables.json
    └── secrets.json
```

## Backend Configuration

Create an S3 bucket for Terraform state:

```bash
aws s3api create-bucket \
  --bucket portkey-tfstate-<account-id> \
  --region us-east-1

aws s3api put-bucket-versioning \
  --bucket portkey-tfstate-<account-id> \
  --versioning-configuration Status=Enabled
```

Create `backend.config`:

```hcl
bucket = "portkey-tfstate-<account-id>"
key    = "portkey-gateway/dev.tfstate"
region = "us-east-1"
```

In `main.tf`:

```hcl
terraform {
  backend "s3" {
    use_lockfile = true
  }
}
```

Initialize with the config file:

```bash
terraform init -backend-config=backend.config
```

## Module Configuration

### Using Inline Variables

Pass configuration directly as HCL:

```hcl
module "portkey_gateway" {
  source = "github.com/Portkey-AI/portkey-gateway-infrastructure//terraform/ecs?ref=v1.0.0"

  environment_variables = {
    gateway = {
      SERVICE_NAME    = "gateway"
      ANALYTICS_STORE = "control_plane"
      LOG_STORE       = "s3_assume"
    }
    data-service = {
      SERVICE_NAME    = "data-service"
      ANALYTICS_STORE = "control_plane"
      LOG_STORE       = "s3_assume"
      HYBRID_DEPLOYMENT = "ON"
    }
  }

  secrets = {
    gateway = {
      PORTKEY_CLIENT_AUTH   = "arn:aws:secretsmanager:us-east-1:123456789012:secret:client-org"
      ORGANISATIONS_TO_SYNC = "arn:aws:secretsmanager:us-east-1:123456789012:secret:client-org"
    }
  }

  # ...
}
```

### Using JSON Files

If you prefer to keep configuration in JSON files (like the clone & deploy approach):

```hcl
module "portkey_gateway" {
  source = "github.com/Portkey-AI/portkey-gateway-infrastructure//terraform/ecs?ref=v1.0.0"

  environment_variables = jsondecode(file("${path.root}/config/environment-variables.json"))
  secrets               = jsondecode(file("${path.root}/config/secrets.json"))

  # ...
}
```

Or use file paths relative to the module directory (for clone & deploy within the repo):

```hcl
module "portkey_gateway" {
  source = "..."

  environment_variables_file_path = "environments/dev/environment-variables.json"
  secrets_file_path               = "environments/dev/secrets.json"

  # ...
}
```

### Using Your Own Variables

Create `variables.tf`:

```hcl
variable "environment" {
  type = string
}

variable "docker_cred_secret_arn" {
  type = string
}
```

Create `terraform.tfvars`:

```hcl
environment             = "prod"
docker_cred_secret_arn  = "arn:aws:secretsmanager:..."
```

Use in `main.tf`:

```hcl
module "portkey_gateway" {
  source = "github.com/Portkey-AI/portkey-gateway-infrastructure//terraform/ecs?ref=v1.0.0"

  environment            = var.environment
  docker_cred_secret_arn = var.docker_cred_secret_arn

  environment_variables = var.environment_variables
  secrets               = var.secrets

  # ...
}
```

## Complete Examples

### Production with All Features

```hcl
module "portkey_gateway" {
  source = "github.com/Portkey-AI/portkey-gateway-infrastructure//terraform/ecs?ref=v1.0.0"

  project_name = "portkey-gateway"
  environment  = "prod"
  aws_region   = "us-east-1"

  docker_cred_secret_arn = "arn:aws:secretsmanager:us-east-1:123456789012:secret:portkey-gateway/prod/docker-credentials"

  environment_variables = {
    gateway = {
      SERVICE_NAME    = "gateway"
      ANALYTICS_STORE = "control_plane"
      LOG_STORE       = "s3_assume"
    }
    data-service = {
      SERVICE_NAME      = "data-service"
      ANALYTICS_STORE   = "control_plane"
      LOG_STORE         = "s3_assume"
      HYBRID_DEPLOYMENT = "ON"
    }
  }

  secrets = {
    gateway = {
      PORTKEY_CLIENT_AUTH   = "arn:aws:secretsmanager:us-east-1:123456789012:secret:portkey-gateway/prod/client-org"
      ORGANISATIONS_TO_SYNC = "arn:aws:secretsmanager:us-east-1:123456789012:secret:portkey-gateway/prod/client-org"
    }
    data-service = {
      PORTKEY_CLIENT_AUTH   = "arn:aws:secretsmanager:us-east-1:123456789012:secret:portkey-gateway/prod/client-org"
      ORGANISATIONS_TO_SYNC = "arn:aws:secretsmanager:us-east-1:123456789012:secret:portkey-gateway/prod/client-org"
    }
  }

  create_new_vpc     = true
  vpc_cidr           = "10.0.0.0/16"
  num_az             = 3
  single_nat_gateway = false

  create_cluster   = true
  instance_type    = "t4g.large"
  min_asg_size     = 2
  max_asg_size     = 10
  desired_asg_size = 3

  server_mode          = "all"
  mcp_gateway_base_url = "https://mcp.example.com"

  gateway_config = {
    desired_task_count = 3
    cpu                = 1024
    memory             = 2048
    gateway_port       = 8787
    mcp_port           = 8788
  }

  gateway_autoscaling = {
    enable_autoscaling        = true
    autoscaling_min_capacity  = 3
    autoscaling_max_capacity  = 20
    target_cpu_utilization    = 70
    target_memory_utilization = 80
    scale_in_cooldown         = 120
    scale_out_cooldown        = 60
  }

  gateway_deployment_configuration = {
    enable_blue_green = true
  }

  dataservice_config = {
    enable_dataservice = true
    desired_task_count = 2
    cpu                = 512
    memory             = 1024
  }

  redis_configuration = {
    redis_type = "aws-elastic-cache"
    cpu        = 256
    memory     = 512
    endpoint   = "prod-redis.xxxxx.cache.amazonaws.com:6379"
    tls        = true
    mode       = "cluster"
  }

  object_storage = {
    log_store_bucket   = "portkey-prod-logs"
    log_exports_bucket = "portkey-prod-exports"
    bucket_region      = "us-east-1"
  }

  create_lb           = true
  internal_lb         = false
  lb_type             = "application"
  tls_certificate_arn = "arn:aws:acm:us-east-1:123456789012:certificate/xxxxxxxx"
  allowed_lb_cidrs    = ["0.0.0.0/0"]

  alb_routing_configuration = {
    enable_host_based_routing = true
    enable_path_based_routing = false
    gateway_host              = "gateway.example.com"
    mcp_host                  = "mcp.example.com"
    mcp_path                  = "/mcp"
    gateway_path              = "/gateway"
  }

  enable_lb_access_logs = true
  lb_access_logs_bucket = "portkey-alb-access-logs"
}
```

### Minimal Development

```hcl
module "portkey_gateway" {
  source = "github.com/Portkey-AI/portkey-gateway-infrastructure//terraform/ecs?ref=v1.0.0"

  project_name = "portkey-gateway"
  environment  = "dev"
  aws_region   = "us-east-1"

  docker_cred_secret_arn = "<DockerCredentialsSecretArn>"

  environment_variables = {
    gateway = {
      SERVICE_NAME    = "gateway"
      ANALYTICS_STORE = "control_plane"
      LOG_STORE       = "s3_assume"
    }
  }

  secrets = {
    gateway = {
      PORTKEY_CLIENT_AUTH   = "<ClientOrgSecretNameArn>"
      ORGANISATIONS_TO_SYNC = "<ClientOrgSecretNameArn>"
    }
  }

  create_new_vpc     = true
  vpc_cidr           = "10.0.0.0/16"
  num_az             = 2
  single_nat_gateway = true

  create_cluster   = true
  instance_type    = "t4g.medium"
  desired_asg_size = 1
  min_asg_size     = 1
  max_asg_size     = 2

  gateway_config = {
    desired_task_count = 1
    cpu                = 256
    memory             = 1024
    gateway_port       = 8787
    mcp_port           = 8788
  }

  server_mode = "gateway"

  redis_configuration = {
    redis_type = "redis"
    cpu        = 256
    memory     = 512
    endpoint   = ""
    tls        = false
    mode       = "standalone"
  }

  object_storage = {
    log_store_bucket = "<dev-logs-bucket>"
    bucket_region    = "us-east-1"
  }

  create_lb   = false
  internal_lb = true
  lb_type     = "network"
}
```

---

## Configuration Guides

### Gateway + MCP (`server_mode = "all"`)

When running Gateway and MCP together:

- Set `server_mode = "all"`
- Set `lb_type = "application"` (ALB required)
- Configure `alb_routing_configuration` with host-based routing (recommended) or path-based routing
- Set `mcp_gateway_base_url` to the public MCP URL

```hcl
module "portkey_gateway" {
  source = "github.com/Portkey-AI/portkey-gateway-infrastructure//terraform/ecs?ref=v1.0.0"

  server_mode          = "all"
  mcp_gateway_base_url = "https://mcp.example.com"

  create_lb = true
  lb_type   = "application"

  alb_routing_configuration = {
    enable_host_based_routing = true
    enable_path_based_routing = false
    gateway_host              = "gateway.example.com"
    mcp_host                  = "mcp.example.com"
    mcp_path                  = "/mcp"
    gateway_path              = "/gateway"
  }

  # ...
}
```

### Amazon ElastiCache Redis

See [ExternalRedis.md](ExternalRedis.md) for connecting to an existing ElastiCache cluster and full configuration examples.

### Deployment Strategies

Blue/Green, Canary, and Linear deployments are configured via `gateway_deployment_configuration`. See [DeploymentStrategies.md](DeploymentStrategies.md) for details.

```hcl
gateway_deployment_configuration = {
  enable_blue_green = true
}

# Canary example
# gateway_deployment_configuration = {
#   enable_blue_green    = false
#   canary_configuration = {
#     canary_bake_time_in_minutes = 5
#     canary_percent              = 10
#   }
# }
```

### Control Plane Integration

The Gateway data plane syncs configuration from the Portkey Control Plane. Supported methods:

- **AWS PrivateLink** (recommended for production)
- **IP whitelisting**

See the [hybrid deployment documentation](https://portkey.ai/docs/self-hosting/hybrid-deployments/aws/eks#integrating-gateway-with-control-plane) for setup steps.

### Amazon Bedrock

Attach IAM policies to the gateway task role for Bedrock access. See [Bedrock.md](Bedrock.md).

```hcl
gateway_task_role_policy_arns = {
  bedrock = "arn:aws:iam::123456789012:policy/portkey-gateway-bedrock"
}
```

---

## Multi-Environment Setup

Manage dev, staging, and prod from one codebase:

```
my-infrastructure/
├── dev/
│   ├── main.tf
│   ├── backend.config
│   └── terraform.tfvars
├── staging/
│   ├── main.tf
│   ├── backend.config
│   └── terraform.tfvars
└── prod/
    ├── main.tf
    ├── backend.config
    └── terraform.tfvars
```

**Shared `main.tf` (identical in each environment):**

```hcl
terraform {
  required_version = ">= 1.13"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }

  backend "s3" {
    use_lockfile = true
  }
}

provider "aws" {
  region = var.aws_region
}

module "portkey_gateway" {
  source = "github.com/Portkey-AI/portkey-gateway-infrastructure//terraform/ecs?ref=v1.0.0"

  environment = var.environment

  environment_variables = var.environment_variables
  secrets               = var.secrets

  # ... use variables for environment-specific values
}
```

**Environment-specific `backend.config`:**

```hcl
# dev/backend.config
bucket = "portkey-tfstate-<account-id>"
key    = "portkey-gateway/dev.tfstate"
region = "us-east-1"

# prod/backend.config
key = "portkey-gateway/prod.tfstate"
```

**Environment-specific `terraform.tfvars`:**

```hcl
# dev/terraform.tfvars
environment = "dev"

# prod/terraform.tfvars
environment = "prod"
```

**Deploy each environment:**

```bash
# Dev
cd dev
terraform init -backend-config=backend.config
terraform apply -var-file=terraform.tfvars

# Prod
cd ../prod
terraform init -backend-config=backend.config
terraform apply -var-file=terraform.tfvars
```

## Version Pinning

Always pin to a specific version in production:

```hcl
# Good - pinned to v1.0.0
source = "github.com/Portkey-AI/portkey-gateway-infrastructure//terraform/ecs?ref=v1.0.0"

# Bad - uses latest from main branch
source = "github.com/Portkey-AI/portkey-gateway-infrastructure//terraform/ecs"

# OK for development only
source = "github.com/Portkey-AI/portkey-gateway-infrastructure//terraform/ecs?ref=main"
```

## Upgrading

### 1. Check Release Notes

Visit https://github.com/Portkey-AI/portkey-gateway-infrastructure/releases

Review:
- New features
- Breaking changes
- Bug fixes
- Required variable changes

### 2. Test in Non-Prod

Update `dev/main.tf`:

```hcl
module "portkey_gateway" {
  source = "github.com/Portkey-AI/portkey-gateway-infrastructure//terraform/ecs?ref=v1.1.0"
  # ...
}
```

```bash
cd dev
terraform init -upgrade
terraform plan
terraform apply
```

Verify the deployment works as expected.

### 3. Promote to Production

After successful testing, update `prod/main.tf`:

```hcl
module "portkey_gateway" {
  source = "github.com/Portkey-AI/portkey-gateway-infrastructure//terraform/ecs?ref=v1.1.0"
  # ...
}
```

```bash
cd prod
terraform init -upgrade
terraform plan  # Review changes carefully
terraform apply
```

### Rollback

If issues occur, revert to the previous version:

```hcl
source = "github.com/Portkey-AI/portkey-gateway-infrastructure//terraform/ecs?ref=v1.0.0"
```

```bash
terraform init -upgrade
terraform apply
```

---

## Next Steps

- **Configuration Details**: See [VARIABLES.md](VARIABLES.md) for all available options
- **External Redis**: See [ExternalRedis.md](ExternalRedis.md) for Amazon ElastiCache
- **Deployment Strategies**: See [DeploymentStrategies.md](DeploymentStrategies.md)
- **Main README**: For clone-and-deploy steps and operational guides
