#########################################################################
#                           PROJECT DETAILS                             #
#########################################################################

project_name = "portkey-gateway"
environment  = "prod"
aws_region   = "us-east-1"                                        
environment_variables_file_path = "environments/prod/environment-variables.json"
secrets_file_path = "environments/prod/secrets.json"

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


# gateway_desired_task = 1                                            # Set desired replica of gateway tasks to run in Gateway Service.
# gateway_cpu          = 256                                          # Set the number of cpu units used by the tasks.
# gateway_memory       = 1024                                         # Set the Amount (in MiB) of memory used by the tasks.
# gateway_enable_autoscaling = true                                 # Set to true to enable autoscaling for Gateway Service. Default false. 
# gateway_min_capacity = 1                                          # Set minimum number of tasks to run in Gateway Service.
# gateway_max_capacity = 3                                          # Set maximmum number of tasks to run in Gateway Service.
# gateway_target_cpu_utilization = 70                               # Set target CPU utilization % that ECS autoscaling should try to maintain for Gateway tasks.
# gateway_target_memory_utilization = 70                            # Set target Memory utilization that ECS autoscaling should try to maintain for Gateway tasks.
# gateway_scale_in_cooldown = 120                                   # Amount of time (seconds) wait after a scale in activity before another scale in activity can start.
# gateway_scale_out_cooldown = 60                                   # Amount of time (seconds) wait after a scale out activity before another scale out activity can start.


###########################################################################
#                       DATA SERVICE CONFIGURATION                        #
###########################################################################

enable_dataservice = false
# dataservice_desired_task = 1                                        # Set desired replica of dataservice tasks to run in Data Service.
# dataservice_cpu          = 256                                      # Set the number of cpu units used by the tasks.
# dataservice_memory       = 1024                                     # Set the Amount (in MiB) of memory used by the tasks.
# dataservice_enable_autoscaling = true                               # Set to true to enable autoscaling for Data Service. Default false. 
# dataservice_min_capacity = 1                                        # Set minimum number of tasks to run in Data Service.
# dataservice_max_capacity = 3                                        # Set maximmum number of tasks to run in Data Service.
# dataservice_target_cpu_utilization = 70                             # Set target CPU utilization % that ECS autoscaling should try to maintain for Data tasks.
# dataservice_target_memory_utilization = 70                          # Set target Memory utilization that ECS autoscaling should try to maintain for Data tasks.
# dataservice_scale_in_cooldown = 120                                 # Amount of time (seconds) wait after a scale in activity before another scale in activity can start.
# dataservice_scale_out_cooldown = 60                                 # Amount of time (seconds) wait after a scale out activity before another scale out activity can start.


###########################################################################
#                           REDIS CONFIGURATION                           #
###########################################################################

redis_type = "redis"                                                  # Set to 'redis' to use 'container' based redis, set to 'aws-elastic-cache' to use AWS ElastiCache as cache store.
# redis_cpu        = 256                                                # Relevant if using built-in container based redis.
# redis_memory     = 1024                                               # Relevant if using built-in container based redis.
# redis_endpoint   = ""                                                 # Only required if using Amazon ElastiCache.
# redis_tls        = false                                              # Set to true if tls is enabled on Amazon ElastiCache
# redis_mode       = "standalone"                                       # Set to 'cluster' if cluster mode is enabled on Amazon ElastiCache, otherwise set it to standalone.



###########################################################################
#                           LOG STORE CONFIGURATION                       #
###########################################################################
object_storage = {
  log_store_bucket   = "<BUCKET_NAME>"                               # Specify the S3 bucket where logs will be stored.
  bucket_region      = "<AWS_REGION>"                                # Specify AWS region where buckets exists.
  # log_exports_bucket = ""                                          # (Optional) Specify bucket for logs, only required if using data service.
  # finetune_bucket    = ""                                          # (Optional) Specify bucket for where dataset will be stored for finetuning LLM models.
}



###########################################################################
#                            AMAZON BEDROCK ACCESS                        #
###########################################################################

# enable_bedrock_access = false

###########################################################################
#                       LOAD BALANCER CONFIGURATION                       #
###########################################################################

# create_nlb = true                                              # Set to true to create a Network Load Balancer (NLB), or false to skip creating one. 
# internal_nlb = true                                            # Set to true to create an internal NLB, or false to create an internet-facing NLB.
# allowed_nlb_cidrs = ["X.X.X.X/Y"]                              # Provide a list of CIDR ranges to whitelist in NLB's Security Group.
# tls_certificate_arn = ""                                       # (Optional) Provide ACM certificate ARN to enable TLS-based listeners.
# enable_blue_green = true                                       # Set to true to enable blue-green deployment for Gateway Service.