################################################################################
# File: terraform/asg.tf
################################################################################


data "aws_ssm_parameter" "ecs_optimized_ami" {
  name = "/aws/service/ecs/optimized-ami/amazon-linux-2023/arm64/recommended"
}

module "autoscaling" {
  source  = "terraform-aws-modules/autoscaling/aws"
  version = "~> 9.0"

  for_each = var.create_cluster ? {
    primary_provider = {
      instance_type              = var.instance_type
      use_mixed_instances_policy = false
      mixed_instances_policy     = null
      user_data = (<<-EOF
        #!/bin/bash
        aws ecs put-account-setting --name awsvpcTrunking --value enabled
        echo ECS_CLUSTER=${var.project_name}-cluster >> /etc/ecs/ecs.config
        echo ECS_ENABLE_CONTAINER_METADATA=true >> /etc/ecs/ecs.config
        echo ECS_ENABLE_TASK_IAM_ROLE=true >> /etc/ecs/ecs.config
      EOF
      )
    }
  } : {}

  name = "${var.project_name}-${each.key}-asg"

  image_id      = jsondecode(data.aws_ssm_parameter.ecs_optimized_ami.value)["image_id"]
  instance_type = each.value.instance_type

  security_groups                 = [module.autoscaling_sg[0].security_group_id]
  user_data                       = base64encode(each.value.user_data)
  ignore_desired_capacity_changes = true

  create_iam_instance_profile = true
  iam_role_name               = "${var.project_name}-${each.key}-role"
  iam_role_description        = "ECS role for ${var.project_name}-${each.key} auto scaling group"
  iam_role_policies = {
    AmazonEC2ContainerServiceforEC2Role = "arn:aws:iam::aws:policy/service-role/AmazonEC2ContainerServiceforEC2Role"
    AmazonSSMManagedInstanceCore        = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
  }

  vpc_zone_identifier = local.private_subnet_ids
  health_check_type   = "EC2"
  min_size            = var.min_asg_size
  max_size            = var.max_asg_size
  desired_capacity    = var.desired_asg_size

  autoscaling_group_tags = {
    AmazonECSManaged = true
  }
  protect_from_scale_in = true
}

# Create Policy allowing EC2 to enabled VPC Trunking
resource "aws_iam_role_policy" "ecs_instance_vpc_trunking_policy" {
  count = var.create_cluster ? 1 : 0
  name  = "ecsInstanceVpcTrunkingPolicy-${var.project_name}-${var.environment}-policy"
  role  = module.autoscaling["primary_provider"].iam_role_name
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ecs:ListAccountSettings",
          "ecs:ListAttributes",
          "ecs:PutAccountSetting"
        ]
        Resource = "*"
      }
    ]
  })
}

# Create security group for EC2 associated with autoscaling group.
module "autoscaling_sg" {
  source  = "terraform-aws-modules/security-group/aws"
  version = "~> 5.0"

  count = var.create_cluster ? 1 : 0

  name        = "${var.project_name}-primary-sg"
  description = "Autoscaling group security group for ${var.project_name}"
  vpc_id      = local.vpc_id

  egress_rules = ["all-all"]

}