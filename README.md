# Portkey Gateway - ECS Deployment

This enterprise-focused deployment guide provides comprehensive instructions for deploying Portkey Gateway on Amazon ECS clusters. Designed to meet the needs of large-scale, mission-critical applications, this guide includes specific recommendations for component sizing, high availability, and integration with monitoring systems.

## Components and Sizing Recommendations

| Component                               | Options                                                                   | Sizing Recommendations                                                                                                                                              |
| --------------------------------------- | ------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------                    |
| AI Gateway                              | Deploy in your ECS cluster using terraform project.                       | Use Amazon ECS t4g.medium worker nodes, each providing at least 2 vCPUs and 4 GiB of memory. For high availability, deploy them across multiple Availability Zones. |
| Logs Store (optional)                   | Amazon S3 or S3-compatible Storage                                        | Each log document is ~10kb in size (uncompressed)                                                                                                                  |
| Cache (Prompts, Configs & Providers)    | Built-in Redis, Amazon ElastiCache for Redis OSS or Valkey                | Deployed within the same VPC as the Portkey Gateway.                                                                                                                |

## Prerequisites

Ensure that following tools and resources are installed and available:

* The [Terraform CLI](https://developer.hashicorp.com/terraform/tutorials/aws-get-started/install-cli) installed.
* [AWS CLI](https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html) installed and configured.
* AWS Account with appropriate permissions

## Create a Portkey Account

1. Go to the [Portkey](https://portkey.ai) website.
2. Sign up for a Portkey account.
3. Once logged in, locate and save your `Organisation ID` for future reference. You can find it in the browser URL:
   `https://app.portkey.ai/organisation/<organisation_id>/`
4. Contact the Portkey AI team and provide your Organisation ID and the email address used during signup.
5. The Portkey team will share the following information with you:
    - Docker credentials for the Gateway images (**username** and **password**).
    - License: **Client Auth Key**.

## Clone Portkey Repository

Clone the Portkey repository containing the terraform project for deploying Portkey Gateway on ECS.

```bash
git clone https://github.com/Portkey-AI/portkey-gateway
cd portkey-gateway/terraform
```

## Store Secrets in AWS Secrets Manager

Use the AWS CloudFormation template to create secrets in AWS Secrets Manager. These secrets will store your Docker credentials, client authentication keys, and other sensitive information.

1. Go [AWS CloudFormation Console](https://us-east-1.console.aws.amazon.com/cloudformation/home?region=us-east-1#/stacks/create) to create the stack.
2. Under **Specify template**, select **Upload a template file**, then upload the `secrets.yaml` CloudFormation template located in the `portkey-gateway/cloudformation/` directory.
3. On the next page, provide the following parameters:
    - **Project Details**
        - Project Name — e.g., `portkey-gateway`
        - Environment — e.g., `dev` or `prod`
    - **Image Credentials**
        - Docker Username - *Provided by Portkey*
        - Docker Password - *Provided by Portkey*
    - **Portkey Integration**
        - Portkey Client Auth - *Provided by Portkey*
        - Organizations - The organization ID obtained after signing up for your Portkey account.
4. Click **Submit** to launch the stack and provision the required resources.
5. After the stack is successfully created, navigate to the **Outputs** section and record the following details.
    - **DockerCredentialsSecretArn**
    - **ClientOrgSecretNameArn**

## Configuration Variables

Navigate to `portkey-gateway/terraform/environments/dev` and update the `dev.tfvars` file to specify your project configuration details. The table below describes all Terraform variables available in this deployment:

| Variable Name | Default | Required | Description |
|--------------|---------|----------|-------------|
| **Project Details** | | | |
| `project_name` | `"portkey"` | No | Name of the Project |
| `environment` | `"dev"` | No | Deployment environment (e.g., dev, prod) |
| `aws_region` | - | **Yes** | AWS region to deploy resources in |
| `environment_variables_file_path` | - | **Yes** | Relative path for environment-variables.json |
| `secrets_file_path` | - | **Yes** | Relative path for secrets.json |
| **Network Configuration** | | | |
| `create_new_vpc` | - | **Yes** | Set to true to create a new VPC. Set to false to use an existing one |
| `vpc_cidr` | `null` | Conditional* | CIDR block for the new VPC (required if create_new_vpc is true) |
| `num_az` | `2` | No | Number of Availability Zones to use. Recommended: at least 2 for high availability |
| `single_nat_gateway` | `true` | No | When true, creates a single NAT Gateway shared across all private subnets, otherwise 1 NAT Gateway per AZ |
| `vpc_id` | `null` | Conditional* | ID of the existing VPC (required if create_new_vpc is false) |
| `public_subnet_ids` | `[]` | Conditional* | List of public subnet IDs (required if create_new_vpc is false) |
| `private_subnet_ids` | `[]` | Conditional* | List of private subnet IDs (required if create_new_vpc is false) |
| **Cluster and Capacity Provider** | | | |
| `create_cluster` | `true` | No | Set to true to create a new ECS cluster. Set to false to use an existing one |
| `cluster_name` | `null` | Conditional* | Name of the cluster (must be provided if create_cluster = false) |
| `capacity_provider_name` | `null` | Conditional* | Name of the cluster capacity provider (must be provided if create_cluster = false) |
| `instance_type` | `"t4g.medium"` | No | EC2 instance type to associate with autoscaling group |
| `max_asg_size` | `3` | No | Maximum number of EC2 in auto scaling group |
| `min_asg_size` | `1` | No | Minimum number of EC2 in auto scaling group |
| `desired_asg_size` | `2` | No | Desired number of EC2 in auto scaling group |
| `target_capacity` | `70` | No | Desired percentage of cluster resources that ECS aims to maintain |
| **Image Configuration** | | | |
| `gateway_image` | `{image="portkeyai/gateway_enterprise", tag="latest"}` | No | Container image to use for the gateway |
| `data_service_image` | `{image="portkeyai/data-service", tag="latest"}` | No | Container image to use for the data service |
| `docker_cred_secret_arn` | - | **Yes** | ARN of AWS Secrets Manager's secret where docker credentials shared by Portkey is stored |
| `redis_image` | `{image="redis", tag="7.2-alpine"}` | No | Container image to use for Redis |
| **Gateway Service Configuration** | | | |
| `gateway_config` | - | **Yes** | Configure details of Gateway Service Tasks (object with: desired_task_count, cpu, memory) |
| `gateway_autoscaling` | - | **Yes** | Configure autoscaling for Gateway Service (object with: enable_autoscaling, autoscaling_max_capacity, autoscaling_min_capacity, target_cpu_utilization, target_memory_utilization, scale_in_cooldown, scale_out_cooldown) |
| **Data Service Configuration** | | | |
| `dataservice_config` | - | **Yes** | Configure details of Data Service Tasks (object with: enable_dataservice, desired_task_count, cpu, memory) |
| `dataservice_autoscaling` | `{enable_autoscaling=false}` | No | Configure autoscaling for Data Service |
| **Redis Configuration** | | | |
| `redis_configuration` | `{redis_type="redis"}` | No | Configure details of Redis to be used (object with: redis_type, cpu, memory, endpoint, tls, mode) |
| **Log Store Configuration** | | | |
| `object_storage` | - | **Yes** | Specify log stores (object with: log_store_bucket, log_exports_bucket, finetune_bucket, bucket_region) |
| `enable_bedrock_access` | `false` | No | Enable access to Bedrock |
| **Load Balancer Configuration** | | | |
| `create_nlb` | `true` | No | Create Network Load Balancer? |
| `internal_nlb` | `true` | No | Create internal load balancer or internet-facing |
| `allowed_nlb_cidrs` | `[]` | No | Provide IP ranges to whitelist in NLB security group |
| `tls_certificate_arn` | `""` | No | ACM certificate ARN to enable TLS-based listeners |
| `enable_blue_green` | `false` | No | Define whether to configure blue-green deployment for gateway with load balancer |

*Conditional: Required based on other variable values (see description for conditions)

## Quick Start

1. Clone this repository
2. Navigate to the terraform directory: `cd terraform`
3. Review and update `environments/dev/dev.tfvars` with your configuration
4. Initialize Terraform: `terraform init -backend-config=environments/dev/backend.config`
5. Plan the deployment: `terraform plan -var-file=environments/dev/dev.tfvars`
6. Apply the configuration: `terraform apply -var-file=environments/dev/dev.tfvars`

## Deploying Portkey Gateway

### Setup Remote S3 Backend

To manage Terraform state securely and enable collaboration across teams, it's recommended to configure a remote backend. Modify the `backend.config` file located in the `terraform/environments/dev` directory.

```hcl
# Replace "<S3_BUCKET_NAME>" with s3 bucket name where terraform state file will be stored.
bucket = "<S3_BUCKET_NAME>"

# Replace "<S3_KEY_PATH>" with key where terraform state file will be written to (e.g., dev/portkey-gateway/terraform.tfstate).
key = "<S3_KEY_PATH>"

# Replace "<AWS_REGION>" with AWS region in which S3 bucket resides (e.g., us-east-1).
region = "<AWS_REGION>"
```

### Initialize Terraform

```bash
cd terraform
terraform init -backend-config=environments/dev/backend.config
```

### Create Terraform Plan

```bash
terraform plan -var-file=environments/dev/dev.tfvars -out=environments/dev/tfplan
```

### Deploy Terraform Plan

Apply the tfplan created in last step to deploy the Gateway resources.

```bash
terraform apply environments/dev/tfplan
```

After a successful deployment, the output will include the DNS name of the created Network Load Balancer. Make sure to note it down for use in later testing.

## Verify the Deployment

To confirm that the deployment was successful, follow these steps:

- Navigate to your Amazon ECS cluster and confirm that the tasks for each created service are running and in a healthy state.

  **Note:** If tasks are in unhealthy state, inspect the Service logs to diagnose potential issues.

- Test Gateway by sending a sample cURL request.

  ```bash
  # Specify LLM provider and Portkey API keys
  export OPENAI_API_KEY=<OPENAI_API_KEY>
  export PORTKEY_API_KEY=<PORTKEY_API_KEY>
  
  # Replace <NETWORK_LOAD_BALANCER_DNS> and <LB_LISTENER_PORT_NUMBER> with the DNS name and listener port of the created load balancer, respectively.
  curl 'http://<NETWORK_LOAD_BALANCER_DNS>:80/v1/chat/completions' \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $OPENAI_API_KEY"  \
  -H "x-portkey-provider: openai" \
  -H "x-portkey-api-key: $PORTKEY_API_KEY"  \
  -d '{
      "model": "gpt-4o-mini",
      "messages": [{"role": "user","content": "What is a fractal?"}]
  }'
  ```

## Integrating Gateway with Control Plane

Portkey supports the following methods for integrating the Control Plane with the Data Plane/Gateway:
- AWS PrivateLink
- IP Whitelisting

For detailed integration instructions, refer to the [full documentation](https://portkey.ai/docs).

## Directory Structure

```
portkey-gateway/
├── cloudformation/
│   ├── secrets.yaml                        # CloudFormation template for creating secrets in AWS Secrets Manager
├── terraform/
│   ├── environments/
│   │   ├── dev/                            # Development environment
│   │   │   ├── dev.tfvars                  # dev input variables
│   │   │   ├── environment-variables.json  # Environment variables for services
│   │   │   └── backend.config              # Remote S3 Backend configuration for Terraform state
│   │   └── prod/                           # Production environment
│   ├── modules/
│   │   └── ecs-service/                    # Reusable ECS service module
│   ├── *.tf                                # Main Terraform configuration files
│   └── variables.tf                        # Variable definitions
└── README.md                               # This file
```

## Notes

- Variables marked as "Conditional" have validation rules that depend on other variables. For example, `vpc_cidr` is required when `create_new_vpc` is true, but not when it's false.
- Default values are shown where applicable. Variables without defaults are required unless they have conditional logic.
- All object-type variables have nested attributes with their own defaults; see the variables.tf file for detailed specifications of object structures.

## Uninstalling Portkey Gateway

```bash
terraform destroy -var-file="environments/dev/dev.tfvars"
```

## License

Copyright © Portkey. All rights reserved.