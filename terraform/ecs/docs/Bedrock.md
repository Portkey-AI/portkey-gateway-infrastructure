# Bedrock Access Configuration

This document provides a simplified guide for configuring AWS assumed roles to access Amazon Bedrock services with Portkey Gateway.

## Overview

To use Amazon Bedrock with Portkey Gateway, you need to configure AWS assumed roles with the appropriate permissions. This allows the gateway to authenticate with AWS and invoke Bedrock models on your behalf.

Alternatively you can use an access token and secret key id, but using assumed roles is a more secure and recommended way to interact with Bedrock.

### Same AWS Account

Use this path when the Portkey gateway and Amazon Bedrock run in **one** AWS account.

## Step 1: Create Bedrock IAM Policy

Create a customer-managed IAM policy. 

**Example policy document:**

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "bedrock:InvokeModel",
        "bedrock:InvokeModelWithResponseStream"
      ],
      "Resource": [
        "arn:aws:bedrock:<region>::foundation-model/<model-id>",
        "arn:aws:bedrock:<region>:<account-id>:provisioned-model/<model-id>"
      ]
    }
  ]
}
```

> Please make a note of the ARN for the IAM policy created.

## Step 2: Attach the policy in Terraform

Add the Bedrock policy ARN to your environment `*.tfvars` file (for example `environments/dev/dev.tfvars`). Terraform attaches it to the **gateway ECS task role** on deploy.

```hcl
gateway_task_role_policy_arns = {
  bedrock = "<IAM_POLICY_ARN>"
}
```
Replace `<IAM_POLICY_ARN>` with the policy ARN from Step 1.

## Step 3: Deploy the gateway

From the `terraform/ecs` directory, run apply:

```bash
terraform apply -var-file=environments/dev/dev.tfvars
```

Update the paths above for your environment.

## Step 4: Create Bedrock integration

In the Portkey portal, create **Amazon Bedrock** or **Bedrock Mantle** LLM integration and choose **AWS Service Role** as auth type.

### Cross AWS Account

Use this path when the gateway runs in AWS account **A** and Bedrock is used in a different account **B**.

## Step 1: Find out IAM Role ARN of ECS Gateway task

```bash
# From the terraform/ecs directory (state must match your environment)
terraform output -raw gateway_task_role_arn
```

Save this value as **`<GATEWAY_TASK_ROLE_ARN>`** (account **A**). The Bedrock account (**B**) must trust this principal so the gateway can assume a role there and call Bedrock.

## Step 2: Create an IAM role in the target account (Bedrock account)

Work in AWS account **B** (where Amazon Bedrock is enabled and models are used).

1. **Create a customer-managed IAM policy** in account **B** that allows the Bedrock actions and `Resource` ARNs you need (foundation models, provisioned models, inference profiles, and so on).

   **Example Bedrock IAM policy document (account B):**

   ```json
   {
     "Version": "2012-10-17",
     "Statement": [
       {
         "Effect": "Allow",
         "Action": [
           "bedrock:InvokeModel",
           "bedrock:InvokeModelWithResponseStream"
         ],
         "Resource": [
           "arn:aws:bedrock:<region>::foundation-model/<model-id>",
           "arn:aws:bedrock:<region>:<account-id>:provisioned-model/<model-id>"
         ]
       }
     ]
   }
   ```

2. **Create an IAM role** in account **B** (for example, `PortkeyGatewayBedrockCrossAccount`) with a **custom trust policy** that allows the gateway task role in account **A** to assume it:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "AWS": "<GATEWAY_TASK_ROLE_ARN>"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
```

- Replace `<GATEWAY_TASK_ROLE_ARN>` with the ARN from **Step 1** above.

3. **Attach** the Bedrock customer-managed policy (from substep 1) to this role. Avoid attaching overly broad AWS managed policies unless your security review requires it.

4. **Copy the new role’s ARN**.

## Step 3: Allow the gateway task role to assume the role in account B

Work in account **A** (where the ECS gateway runs).

1. **Create a customer-managed IAM policy** in account **A** that allows assuming only the Bedrock role in **B**:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": "sts:AssumeRole",
      "Resource": "arn:aws:iam::<ACCOUNT_B>:role/<BEDROCK_ACCESS_ROLE_NAME>"
    }
  ]
}
```

Use the exact role ARN from **Step 2** in `Resource` (you can use the full role ARN string).

2. **Attach that policy** to the gateway ECS task role via Terraform. In your `*.tfvars` for account **A**:

```hcl
gateway_task_role_policy_arns = {
  bedrock_assume_role = "<IAM_POLICY_ARN_FROM_SUBSTEP_1>"
}
```

Replace with the policy ARN from substep 1. Apply Terraform so the gateway tasks pick up the new policy.

## Step 4: Create Bedrock integration

In the Portkey portal, add an LLM integration for **Amazon Bedrock** or **Bedrock Mantle**. Choose **AWS Assumed Role** as auth type and enter the **IAM role ARN from account B** in AWS Role ARN field.
