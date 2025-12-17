# Package the Lambda function code
data "archive_file" "ecs_hook_lambda_file" {
  count       = var.gateway_lifecycle_hook.enable_lifecycle_hook ? 1 : 0
  type        = "zip"
  source_file = "${path.module}/lambda/lifecycle-hook/index.py"
  output_path = "${path.module}/lambda/lifecycle-hook/function.zip"
}

# Lambda for handling ECS Lifecycle Hook
resource "aws_lambda_function" "ecs_hook_lambda" {
  count            = var.gateway_lifecycle_hook.enable_lifecycle_hook ? 1 : 0
  filename         = data.archive_file.ecs_hook_lambda_file[0].output_path
  function_name    = "${var.project_name}-lifecycle-hook-lambda-${var.environment}"
  role             = aws_iam_role.ecs_hook_lambda_execution_role[0].arn
  handler          = "index.handler"
  source_code_hash = data.archive_file.ecs_hook_lambda_file[0].output_base64sha256
  runtime          = "python3.14"
  timeout          = 30
}