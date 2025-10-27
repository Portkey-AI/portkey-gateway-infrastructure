################################################################################
# File: terraform/iam.tf
################################################################################

resource "aws_iam_policy" "s3_access_policy" {
  name        = "portkey-gateway-s3-access-policy-${random_id.suffix.hex}"
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
  name        = "portkey-bedrock-access-policy-${random_id.suffix.hex}"
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

