# Terraform Variables Reference

This document describes all available Terraform variables for deploying Portkey Gateway on AWS ECS.

## Variable Notation

Service configuration variables use object notation. Example:
```hcl
gateway_config = {
  cpu                = 256
  memory             = 1024
  desired_task_count = 1
}
```

##Project Details

| Variable | Default | Required | Description |
|----------|---------|----------|-------------|
| `project_name` | `"portkey"` | No | Project name used in resource naming |
| `environment` | `"dev"` | No | Deployment environment (dev, prod, etc.) |
| `aws_region` | - | **Yes** | AWS region for deployment |
| `environment_variables_file_path` | - | **Yes** | Path to environment-variables.json file |
| `secrets_file_path` | - | **Yes** | Path to secrets.json file with AWS Secrets Manager ARNs |

## Network Configuration

| Variable | Default | Required | Description |
|----------|---------|----------|-------------|
| `create_new_vpc` | - | **Yes** | Create new VPC (true) or use existing (false) |
| `vpc_cidr` | `null` | Conditional | CIDR for new VPC (required if `create_new_vpc = true`) |
| `num_az` | `2` | No | Number of Availability Zones (minimum 2 recommended) |
| `single_nat_gateway` | `true` | No | Use one NAT Gateway (true) or one per AZ (false) |
| `vpc_id` | `null` | Conditional | Existing VPC ID (required if `create_new_vpc = false`) |
| `public_subnet_ids` | `[]` | Conditional | Public subnet IDs (required if `create_new_vpc = false`) |
| `private_subnet_ids` | `[]` | Conditional | Private subnet IDs (required if `create_new_vpc = false`) |

## Cluster and Capacity Provider

| Variable | Default | Required | Description |
|----------|---------|----------|-------------|
| `create_cluster` | `true` | No | Create new ECS cluster (true) or use existing (false) |
| `cluster_name` | `null` | Conditional | Cluster name (required if `create_cluster = false`) |
| `capacity_provider_name` | `null` | Conditional | Capacity provider name (required if `create_cluster = false`) |
| `instance_type` | `"t4g.medium"` | No | EC2 instance type for ECS worker nodes |
| `max_asg_size` | `3` | No | Maximum EC2 instances in Auto Scaling Group |
| `min_asg_size` | `1` | No | Minimum EC2 instances in Auto Scaling Group |
| `desired_asg_size` | `2` | No | Desired EC2 instances in Auto Scaling Group |
| `target_capacity` | `70` | No | Target percentage of cluster resources ECS should maintain |

## Docker Image Configuration

| Variable | Default | Required | Description |
|----------|---------|----------|-------------|
| `gateway_image.image` | `"portkeyai/gateway_enterprise"` | No | Gateway container image |
| `gateway_image.tag` | `"latest"` | No | Gateway image tag/version |
| `data_service_image.image` | `"portkeyai/data-service"` | No | Data Service container image |
| `data_service_image.tag` | `"latest"` | No | Data Service image tag/version |
| `docker_cred_secret_arn` | - | **Yes** | AWS Secrets Manager ARN for Docker credentials |
| `redis_image.image` | `"redis"` | No | Redis container image |
| `redis_image.tag` | `"7.2-alpine"` | No | Redis image tag/version |

## Gateway Service Configuration

| Variable | Default | Required | Description |
|----------|---------|----------|-------------|
| `server_mode` | `"gateway"` | No | Gateway mode: `gateway` (8787), `mcp` (8788), or `both`. When `both`, requires `lb_type = "application"` |
| `gateway_config.desired_task_count` | `1` | No | Number of Gateway tasks |
| `gateway_config.cpu` | `256` | No | CPU units (256 = 0.25 vCPU, 1024 = 1 vCPU) |
| `gateway_config.memory` | `1024` | No | Memory in MiB |
| `gateway_autoscaling.enable_autoscaling` | `false` | No | Enable ECS autoscaling |
| `gateway_autoscaling.min_capacity` | `1` | No | Minimum tasks when autoscaling |
| `gateway_autoscaling.max_capacity` | `3` | No | Maximum tasks when autoscaling |
| `gateway_autoscaling.target_cpu_utilization` | `70` | No | Target CPU % for autoscaling triggers |
| `gateway_autoscaling.target_memory_utilization` | `70` | No | Target memory % for autoscaling triggers |
| `gateway_autoscaling.scale_in_cooldown` | `120` | No | Cooldown seconds after scale-in |
| `gateway_autoscaling.scale_out_cooldown` | `60` | No | Cooldown seconds after scale-out |

## Data Service Configuration

| Variable | Default | Required | Description |
|----------|---------|----------|-------------|
| `enable_dataservice` | `false` | No | Deploy Data Service |
| `dataservice_config.desired_task_count` | `1` | No | Number of Data Service tasks |
| `dataservice_config.cpu` | `256` | No | CPU units (256 = 0.25 vCPU) |
| `dataservice_config.memory` | `1024` | No | Memory in MiB |
| `dataservice_autoscaling.enable_autoscaling` | `false` | No | Enable autoscaling |
| `dataservice_autoscaling.min_capacity` | `1` | No | Minimum tasks |
| `dataservice_autoscaling.max_capacity` | `3` | No | Maximum tasks |
| `dataservice_autoscaling.target_cpu_utilization` | `70` | No | Target CPU % |
| `dataservice_autoscaling.target_memory_utilization` | `70` | No | Target memory % |
| `dataservice_autoscaling.scale_in_cooldown` | `120` | No | Scale-in cooldown (seconds) |
| `dataservice_autoscaling.scale_out_cooldown` | `60` | No | Scale-out cooldown (seconds) |

## Redis Configuration

| Variable | Default | Required | Description |
|----------|---------|----------|-------------|
| `redis_type` | `"redis"` | No | Cache type: `redis` (containerized) or `aws-elasti-cache` (ElastiCache) |
| `redis_endpoint` | `""` | Conditional | ElastiCache endpoint (required if `redis_type = "aws-elasti-cache"`)* |
| `redis_cpu` | `256` | No | CPU units for containerized Redis |
| `redis_memory` | `512` | No | Memory (MiB) for containerized Redis |
| `redis_tls_enabled` | `false` | No | Enable TLS for Redis connections |
| `redis_mode` | `"standalone"` | No | Redis mode: `standalone` or `cluster` |

*For cluster mode, use Configuration Endpoint. For standalone, use Primary Endpoint. See [AWS ElastiCache Endpoints](https://docs.aws.amazon.com/AmazonElastiCache/latest/dg/Endpoints.html).

## Log Store Configuration

| Variable | Default | Required | Description |
|----------|---------|----------|-------------|
| `object_storage.log_store_bucket` | - | **Yes** | S3 bucket for log storage |
| `object_storage.log_exports_bucket` | - | **Yes** | S3 bucket for log exports |
| `object_storage.finetune_bucket` | - | **Yes** | S3 bucket for fine-tuning data |
| `object_storage.bucket_region` | - | **Yes** | AWS region for S3 buckets |
| `enable_bedrock_access` | `false` | No | Enable AWS Bedrock API access |

## Load Balancer Configuration

| Variable | Default | Required | Description |
|----------|---------|----------|-------------|
| `create_lb` | `true` | No | Create load balancer for Gateway |
| `lb_type` | `"network"` | No | Load balancer type: `network` (NLB) or `application` (ALB). Use `application` when `server_mode = "both"` |
| `internal_lb` | `true` | No | Internal LB (true) or internet-facing (false) |
| `allowed_lb_cidrs` | `[]` | No | IP ranges for LB security group. Defaults to VPC CIDR (internal) or 0.0.0.0/0 (internet-facing) |
| `enable_lb_access_logs` | `false` | No | Enable LB access logs to S3 |
| `lb_access_logs_bucket` | `""` | Conditional | S3 bucket for access logs (required if `enable_lb_access_logs = true`) |
| `lb_access_logs_prefix` | `""` | No | S3 prefix for access logs |
| `tls_certificate_arn` | `""` | No | ACM certificate ARN for TLS/HTTPS |
| `enable_blue_green` | `false` | No | Enable Blue/Green deployment. **Only works with ALB** (`lb_type = "application"`). NLB uses rolling updates |

## Host-Based Routing (ALB Only)

| Variable | Default | Required | Description |
|----------|---------|----------|-------------|
| `llm_gateway_host` | `""` | Conditional | Domain for LLM Gateway (required when `lb_type = "application"` and `server_mode` is `gateway` or `both`) |
| `mcp_gateway_host` | `""` | Conditional | Domain for MCP Gateway (required when `lb_type = "application"` and `server_mode` is `mcp` or `both`) |

## Important Notes

### Blue/Green Deployment
- **ALB**: Fully supported with CodeDeploy-style Blue/Green deployment
  - Creates blue and green target groups
  - Uses test listener (port 8080) for validation
  - Automatic traffic shifting after validation
- **NLB**: Uses standard ECS rolling updates (Blue/Green not supported in current implementation)
  - Gradual task replacement
  - No separate test listener
  - Set `enable_blue_green = false` for NLB

### Server Modes
- `gateway`: Gateway listens on port 8787 only (LLM Gateway)
- `mcp`: Gateway listens on port 8788 only (MCP protocol)
- `both`: Gateway listens on both ports (requires ALB with host-based routing)

### Validation Rules
- When `server_mode = "both"`, `lb_type` must be `"application"`
- When `lb_type = "application"` and `server_mode` includes services, host variables are required
- When `enable_lb_access_logs = true`, `lb_access_logs_bucket` is required
- ElastiCache endpoint required when `redis_type = "aws-elasti-cache"`

