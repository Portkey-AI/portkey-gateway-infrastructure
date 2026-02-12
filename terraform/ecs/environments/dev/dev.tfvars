#########################################################################
#                           PROJECT DETAILS                             #
#########################################################################

project_name = "portkey-gateway"
environment  = "dev"
aws_region   = "us-east-1"                                        
environment_variables_file_path = "environments/dev/environment-variables.json"
secrets_file_path = "environments/dev/secrets.json"

#########################################################################
#                         NETWORK CONFIGURATION                         #
#########################################################################

# Provide following details to create new VPC
create_new_vpc = true                                           # Set to true for creating new VPC, false for deploying Portkey in new VPC.
                                                       
vpc_cidr           = "10.0.0.0/16"                              # Specify the CIDR block for the new VPC. Recommended to have CIDR of atleast /20 in size.
num_az             = 2                                          # Number of Availability Zones to use. At least 2 AZs are recommended for high availability. One public and one private subnet will be created per AZ.
single_nat_gateway = true                                       # Set to true to create a single NAT Gateway shared across all private subnets in different AZs, false for one NAT Gateway per AZ.


# # Provide following details if using existing VPC
# create_new_vpc = false                                         # Set to true for creating new VPC, false for deploying Portkey in new VPC.

# vpc_id             = "vpc-1a2b3c4d5e6f"                        # Provide VPC Id where Portkey Gateway will be deployed. 
# public_subnet_ids  = ["subnet-1x2y3z", "subnet-1x2y3z"]        # Provide Public Subnets IDs. Subnets must be in same VPC.
# private_subnet_ids = ["subnet-1x2y3z", "subnet-1x2y3z"]        # Provide Private Subnets IDs. Subnets must be in same VPC.
# create_cluster = true


###########################################################################
#                      CLUSTER AND CAPACITY PROVIDER                      #
###########################################################################
# Provide following details to create new ECS Cluster and EC2 Autoscaling based capacity provider.
create_cluster   = true
instance_type    = "t4g.medium"                                 # Provide EC2 instance type to use for the cluster.
max_asg_size     = 2                                            # Maximum size of the Auto Scaling Group.
min_asg_size     = 1                                            # Minimum size of the Auto Scaling Group.
desired_asg_size = 1                                            # Desired size of the Autoscaling Group.
target_capacity  = 100                                          # Provide the capacity which ECS should try to maintain - (0-100)



# # Provide following details to create new ECS Cluster and EC2 Autoscaling based capacity provider.
# create_cluster = false
# cluster_name = "my-cluster-name"                                # Set the name of exising ECS cluster.
# capacity_provider_name = "my-capacity-provider-name"            # Name of capacity provider to use for deploying Portkey services


###########################################################################
#                         DOCKER IMAGE CONFIGURATION                      #
###########################################################################
gateway_image = {
  image = "portkeyai/gateway_enterprise"
  tag   = "latest"
}

data_service_image = {
  image = "portkeyai/data-service"
  tag   = "latest"
}

# Provide the Secret ARN obtained from output section of AWS CloudFormation Stack.
docker_cred_secret_arn = "<DockerCredentialsSecretArn>"            # Replace with your AWS Secrets Manager Secret ARN containing Docker Hub credentials for pulling Portkey private images.

redis_image = {
  image = "redis"
  tag   = "7.2-alpine"
}

###########################################################################
#                     GATEWAY SERVICE CONFIGURATION                       #
###########################################################################

gateway_config = {
  desired_task_count = 1                                            # Set desired replica of gateway tasks to run in Gateway Service.
  cpu                = 256                                          # Set the number of cpu units used by the tasks.
  memory             = 1024                                         # Set the Amount (in MiB) of memory used by the tasks.
  gateway_port       = 8787                                          # Port on which Gateway application will listen (internally).
  mcp_port           = 8788                                          # Port on which MCP application will listen (internally).
}

# gateway_autoscaling = {
#   enable_autoscaling        = false                                 # Set to true to enable autoscaling for Gateway Service. Default false.
#   autoscaling_min_capacity  = 1                                     # Set minimum number of tasks to run in Gateway Service.
#   autoscaling_max_capacity  = 3                                     # Set maximum number of tasks to run in Gateway Service.
#   target_cpu_utilization    = 70                                    # Set target CPU utilization % that ECS autoscaling should try to maintain for Gateway tasks.
#   target_memory_utilization = 70                                    # Set target Memory utilization that ECS autoscaling should try to maintain for Gateway tasks.
#   scale_in_cooldown         = 120                                   # Amount of time (seconds) wait after a scale in activity before another scale in activity can start.
#   scale_out_cooldown        = 60                                    # Amount of time (seconds) wait after a scale out activity before another scale out activity can start.
# }

gateway_deployment_configuration = {                                         
  enable_blue_green = true                                            # Set to true to enable blue-green deployment for Gateway Service.
  # canary_configuration = {
  #   canary_bake_time_in_minutes = 100
  #   canary_percent = 200
  # }
  # linear_configuration = {
  #   step_bake_time_in_minutes = 100
  #   step_percent = 10
  # }
}
# gateway_deployment_circuit_breaker = {
#   enable   = true
#   rollback = true
# }

# gateway_lifecycle_hook = {
#   enable_lifecycle_hook = false                                     # Set to true to enable lifecycle hook for Gateway Service.
#   lifecycle_hook_stages = []                                        # Specify lifecycle hook stages (e.g., ["PRE_SCALE_UP", "PRE_SCALE_DOWN"])
# }

###########################################################################
#                       DATA SERVICE CONFIGURATION                        #
###########################################################################

dataservice_config = {
  enable_dataservice = false                                        # Set to true to enable Data Service.
  desired_task_count = 1                                            # Set desired replica of dataservice tasks to run in Data Service.
  cpu                = 256                                          # Set the number of cpu units used by the tasks.
  memory             = 1024                                         # Set the Amount (in MiB) of memory used by the tasks.
}

# dataservice_autoscaling = {
#   enable_autoscaling        = false                                 # Set to true to enable autoscaling for Data Service. Default false.
#   autoscaling_min_capacity  = 1                                     # Set minimum number of tasks to run in Data Service.
#   autoscaling_max_capacity  = 3                                     # Set maximum number of tasks to run in Data Service.
#   target_cpu_utilization    = 70                                    # Set target CPU utilization % that ECS autoscaling should try to maintain for Data tasks.
#   target_memory_utilization = 70                                    # Set target Memory utilization that ECS autoscaling should try to maintain for Data tasks.
#   scale_in_cooldown         = 120                                   # Amount of time (seconds) wait after a scale in activity before another scale in activity can start.
#   scale_out_cooldown        = 60                                    # Amount of time (seconds) wait after a scale out activity before another scale out activity can start.
# }

###########################################################################
#                           REDIS CONFIGURATION                           #
###########################################################################

redis_configuration = {
  redis_type = "redis"                                              # Set to 'redis' to use 'container' based redis, set to 'aws-elastic-cache' to use AWS ElastiCache as cache store.
  cpu        = 256                                                  # Relevant if using built-in container based redis.
  memory     = 512                                                  # Relevant if using built-in container based redis.
  endpoint   = ""                                                   # Only required if using Amazon ElastiCache.
  tls        = false                                                # Set to true if tls is enabled on Amazon ElastiCache
  mode       = "standalone"                                         # Set to 'cluster' if cluster mode is enabled on Amazon ElastiCache, otherwise set it to standalone.
}

###########################################################################
#                           LOG STORE CONFIGURATION                       #
###########################################################################
object_storage = {
  log_store_bucket   = "<BUCKET_NAME>"                               # Specify the S3 bucket where logs will be stored.
  bucket_region      = "<AWS_REGION>"                                # Specify AWS region where buckets exists.
  # log_exports_bucket = ""                                          # (Optional) (Optional) Specify bucket for logs exports, if not specified `log_store_bucket` will be used for log exports.
  # finetune_bucket    = ""                                          # (Optional) Specify bucket where dataset will be stored for finetuning LLM models.
}

###########################################################################
#                   AMAZON BEDROCK ACCESS CONFIGURATION                   #
###########################################################################

# enable_bedrock_access = false

###########################################################################
#                       LOAD BALANCER CONFIGURATION                       #
###########################################################################

create_lb               = false                                  # Set to true to create a Load Balancer, or false to skip creating one.
internal_lb             = true                                   # Set to true to create an internal LB, or false to create an internet-facing LB.
lb_type                 = "network"                              # Set to 'application' or 'network' to specify load balancer type.
# allowed_lb_cidrs        = ["X.X.X.X/Y"]                        # Provide a list of CIDR ranges to whitelist in LB's Security Group.
# tls_certificate_arn     = ""                                   # (Optional) Provide ACM certificate ARN to enable TLS-based listeners.

# Access Logs Configuration
# enable_lb_access_logs   = false                                # Set to true to enable access logs for the Load Balancer.
# lb_access_logs_bucket   = ""                                   # S3 bucket name for storing Load Balancer access logs (required if enable_lb_access_logs is true).
# lb_access_logs_prefix   = ""                                   # S3 bucket prefix for Load Balancer access logs (optional).

###########################################################################
#                           ROUTING CONFIGURATION                         #
###########################################################################

# When server_mode = "all", ALB with host-based or path-based routing must be enabled.
# Define routing rules to route traffic based on host headers and paths.

server_mode = "gateway"                                          # Specify server mode: 'gateway', 'mcp', or 'all'.

# alb_routing_configuration = {
#   enable_path_based_routing = false                              # Set to true to enable path-based routing.
#   enable_host_based_routing = false                              # Set to true to enable host-based routing.
#   mcp_path                  = "/mcp"                             # Path for MCP service (relevant if path-based routing is enabled).
#   gateway_path              = "/gateway"                         # Path for Gateway service (relevant if path-based routing is enabled).
#   mcp_host                  = ""                                 # Host for MCP service (relevant if host-based routing is enabled).
#   gateway_host              = ""                                 # Host for Gateway service (relevant if host-based routing is enabled).
# }