# Blue-Green Deployment

This document outlines a simplified approach to setting up blue-green deployments for the Portkey Gateway.

## Overview

A blue-green deployment strategy can be used to roll out new versions of the Portkey Gateway Service by running two identical environments—blue (current tasks) and green (new tasks)—and switching traffic between them. This approach reduces deployment risk and allows quick rollback in case of issues.

## Setup 
To enable blue-green deployment, set `enable_blue_green` to `true` in the **[env].tfvars** file. 
When this parameter is set to `false`, the project defaults to **Rolling Update** deployment strategy.

### Lifecycle Hooks

ECS service deployments move through several lifecycle stages including `PRE_SCALE_UP` and `PRE_TEST_TRAFFIC_SHIFT`. Lifecycle hooks allow you to pause deployments at these stages to perform validation tests or run custom logic before proceeding. For example, you can add a manual approval step before shifting production traffic to the new deployment. This capability is implemented using AWS Lambda.

This project includes a blank [lambda function](../lambda/lifecycle-hook/index.py) that you can customize to implement your validation logic at different deployment stages.

To enable lifecycle hooks, configure the following parameters in your **[env].tfvars** file:
```sh
gateway_lifecycle_hook = {
    enable_lifecycle_hook = true
    lifecycle_hook_stages = ["RECONCILE_SERVICE", "PRE_SCALE_UP"]    
}
```

The Lambda function will be invoked by ECS at each stage specified in the `lifecycle_hook_stages` field. For more details refer following [AWS ECS documentation](https://docs.aws.amazon.com/AmazonECS/latest/developerguide/deployment-lifecycle-hooks.html).

**Note**: Blue-Green deployment is supported for Gateway service deployment only.
