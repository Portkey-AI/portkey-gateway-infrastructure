# ============================================================================
# FILE: modules/ecs-service/iam.tf
# ============================================================================

resource "aws_iam_role" "ecs_task_role" {
  name = "ecsTaskRole-${var.project_name}-${random_id.suffix.hex}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = ["ecs-tasks.amazonaws.com"]
        }
        Action = "sts:AssumeRole"
        Condition = {
          ArnLike = {
            "aws:SourceArn" = "arn:aws:ecs:${local.region}:${local.account_id}:*"
          }
          StringEquals = {
            "aws:SourceAccount" = local.account_id
          }
        }
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "task_role_policies" {
  for_each = local.task_policy_map

  role       = aws_iam_role.ecs_task_role.name
  policy_arn = each.value
}

# Minimal inline policy to allow ECS Exec (SSM session channels only).
# Replaces the broad AmazonSSMManagedInstanceCore managed policy, which also
# grants ssm:GetParameter*/GetDocument/etc. on "*" and is not needed for ECS Exec.
resource "aws_iam_role_policy" "task_exec_policies" {
  count = var.ecs_service_config.enable_execute_command ? 1 : 0

  name = "ecs-exec-ssmmessages"
  role = aws_iam_role.ecs_task_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ssmmessages:CreateControlChannel",
          "ssmmessages:CreateDataChannel",
          "ssmmessages:OpenControlChannel",
          "ssmmessages:OpenDataChannel"
        ]
        Resource = "*"
      }
    ]
  })
}



# Create execution role
resource "aws_iam_role" "ecs_execution_role" {
  name = "ecsExecutionRole-${var.project_name}-${random_id.suffix.hex}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = ["ecs-tasks.amazonaws.com"]
        }
        Action = "sts:AssumeRole"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "ecs_execution_role_policy" {
  role       = aws_iam_role.ecs_execution_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

# Dynamic policy for all container secrets
resource "aws_iam_policy" "secret_access_policy" {
  count = length(local.all_secret_arns) > 0 ? 1 : 0

  name_prefix = "ecs-task-secrets-access-"
  description = "Allow ECS task to read Secrets Manager secrets referenced by containers"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "secretsmanager:GetSecretValue",
          "secretsmanager:DescribeSecret",
          "secretsmanager:ListSecretVersionIds"
        ]
        Resource = local.all_secret_arns
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "task_role_policy_attach" {
  count      = length(local.all_secret_arns) > 0 ? 1 : 0
  role       = aws_iam_role.ecs_execution_role.name
  policy_arn = aws_iam_policy.secret_access_policy[0].arn
}

# Create role allowing ECS to manage load balancer resources
resource "aws_iam_role" "ecs_load_balancer_role" {
  count = var.load_balancer_config.create_lb ? 1 : 0
  name  = "ecsInfrastructureRoleForLoadBalancers-${local.service_name}-${random_id.suffix.hex}"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ecs.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "ecs_load_balancer_policy" {
  count      = var.load_balancer_config.create_lb ? 1 : 0
  role       = aws_iam_role.ecs_load_balancer_role[0].name
  policy_arn = "arn:aws:iam::aws:policy/AmazonECSInfrastructureRolePolicyForLoadBalancers"
}

