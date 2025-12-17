################################################################################
# File: terraform/iam.tf
################################################################################

resource "aws_iam_policy" "s3_access_policy" {
  name        = "${var.project_name}-gateway-s3-access-policy-${var.environment}"
  path        = "/"
  description = "Policy allowing access to s3 log stores"


  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "s3:GetObject",
          "s3:PutObject"
        ]
        Effect = "Allow"
        Resource = [
          for bucket in toset(compact([
            local.log_store_bucket,
            local.log_exports_bucket,
            local.finetune_bucket
          ])) : "arn:aws:s3:::${bucket}/*"
        ]
      }
    ]
  })
}

resource "aws_iam_policy" "bedrock_access_policy" {
  count       = var.enable_bedrock_access ? 1 : 0
  name        = "${var.project_name}-bedrock-access-policy-${var.environment}"
  path        = "/"
  description = "Policy allowing portkey gateway access to bedrock models"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "bedrock:InvokeModel",
          "bedrock:InvokeModelWithResponseStream"
        ]
        Effect   = "Allow"
        Resource = ["*"]
      }
    ]
  })
}


# IAM Role for ecs hook lambda
resource "aws_iam_role" "ecs_hook_lambda_execution_role" {
  count = var.gateway_lifecycle_hook.enable_lifecycle_hook ? 1 : 0
  name  = "${var.project_name}-ecs-hook-lambda-execution-role-${var.environment}"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      }
    ]
  })
}

# Attach CloudWatch Logs Policy to ecs hook lambda role.
resource "aws_iam_role_policy" "cloudwatch_log_access_policy" {
  count = var.gateway_lifecycle_hook.enable_lifecycle_hook ? 1 : 0
  name  = "${var.project_name}-ecs-hook-lambda-cloudwatch-log-access-policy-${var.environment}"
  role  = aws_iam_role.ecs_hook_lambda_execution_role[0].id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow",
        Action   = "logs:CreateLogGroup",
        Resource = "arn:aws:logs:${local.region}:${local.account_id}:*"
      },
      {
        Effect = "Allow",
        Action = [
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ],
        Resource = [
          "arn:aws:logs:${local.region}:${local.account_id}:log-group:/aws/lambda/${var.project_name}-lifecycle-hook-lambda-${var.environment}:*"
        ]
      }
    ]
  })
}

# Role for ECS to trigger Lifecycle hooks
resource "aws_iam_role" "ecs_hook_role" {
  count = var.gateway_lifecycle_hook.enable_lifecycle_hook ? 1 : 0
  name  = "${var.project_name}-ecs-hook-role-${var.environment}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "ecs.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })
  lifecycle {
    create_before_destroy = true
  }
}

# LambdaInvoke policy to ECS Role
resource "aws_iam_role_policy" "lambda_access_policy" {
  name = "LambdaAccessPolicy"
  role = aws_iam_role.ecs_hook_role[0].id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow",
        Action = [
          "lambda:InvokeFunction",
          "lambda:InvokeAsync"
        ],
        Resource = aws_lambda_function.ecs_hook_lambda[0].arn
      }
    ]
  })
}