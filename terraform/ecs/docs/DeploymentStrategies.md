# Deployment Strategies

This document outlines the deployment strategies available for the Portkey Gateway on Amazon ECS.

## Overview

The Portkey Gateway infrastructure supports multiple deployment strategies to accommodate different risk tolerances and operational requirements. Each strategy offers different trade-offs between deployment speed, risk mitigation, and rollback capabilities.

## Available Strategies

| Strategy | Description 
|----------|-------------|
| **Rolling** | Gradual replacement of tasks|
| **Blue/Green** | Instant traffic switch between environments |
| **Canary** | Small percentage tested before full rollout |
| **Linear** | Incremental traffic shift in equal steps |

## Configuration

Deployment strategy is configured via the `gateway_deployment_configuration` variable in your `[env].tfvars` file.

### Rolling Deployment (Default)

When no advanced deployment configuration is specified, the project uses the **Rolling Update** strategy.

```hcl
# Rolling deployment - default behavior when deployment_configuration is not set
# or when all strategy options are disabled/null

gateway_deployment_configuration = null

# Or explicitly with no strategies enabled:
gateway_deployment_configuration = {
  enable_blue_green    = false
  canary_configuration = null
  linear_configuration = null
}
```

**How it works:**
1. ECS gradually stops old tasks and starts new tasks
2. Maintains `deployment_minimum_healthy_percent` during rollout
3. Can scale up to `deployment_maximum_percent` during deployment

---

## Blue/Green Deployment

Blue/Green deployment runs two identical environments and instantly switches all traffic from the current (blue) to the new (green) version.

### Setup

```hcl
gateway_deployment_configuration = {
  enable_blue_green = true
}
```

### How It Works

```
┌─────────────────────────────────────────────────────────────────────┐
│                        Load Balancer                                │
│                                                                     │
│    Production Listener (443/80)    Test Listener (8443/8080)        │
│              │                              │                       │
│              ▼                              ▼                       │
│    ┌─────────────────┐            ┌─────────────────┐               │
│    │  Blue Target    │            │  Green Target   │               │
│    │  Group (v1)     │            │  Group (v2)     │               │
│    └────────┬────────┘            └────────┬────────┘               │
│             │                              │                        │
│             ▼                              ▼                        │
│    ┌─────────────────┐            ┌─────────────────┐               │
│    │  ECS Tasks      │            │  ECS Tasks      │               │
│    │  (Current)      │            │  (New Version)  │               │
│    └─────────────────┘            └─────────────────┘               │
└─────────────────────────────────────────────────────────────────────┘
```

**Deployment Flow:**
1. New tasks (green) are deployed alongside existing tasks (blue)
2. Green tasks receive traffic on test listener (port 8443/8080)
3. Validation can be performed against test endpoint
4. Traffic is instantly switched from blue to green
5. Blue tasks are terminated after successful switchover

### Listener Ports

| Listener | With TLS | Without TLS |
|----------|----------|-------------|
| Production | 443 | 80 |
| Test | 8443 | 8080 |

---

## Canary Deployment

Canary deployment routes a small percentage of traffic to the new version before gradually shifting all traffic.

### Setup

```hcl
gateway_deployment_configuration = {
  enable_blue_green = false
  canary_configuration = {
    canary_bake_time_in_minutes = 10   # Wait time after canary starts
    canary_percent              = 10   # Initial traffic percentage to canary
  }
}
```

### How It Works

```
Phase 1: Canary (10% traffic)
┌────────────────────────────────────────────┐
│              Load Balancer                 │
│                    │                       │
│         ┌─────────┴─────────┐              │
│         │                   │              │
│        90%                 10%             │
│         ▼                   ▼              │
│  ┌─────────────┐     ┌─────────────┐       │
│  │ Blue (v1)   │     │ Green (v2)  │       │
│  │ Production  │     │ Canary      │       │
│  └─────────────┘     └─────────────┘       │
└────────────────────────────────────────────┘

Phase 2: After bake time - Full rollout (100% traffic)
┌────────────────────────────────────────────┐
│              Load Balancer                 │
│                    │                       │
│                  100%                      │
│                    ▼                       │
│             ┌─────────────┐                │
│             │ Green (v2)  │                │
│             │ Production  │                │
│             └─────────────┘                │
└────────────────────────────────────────────┘
```

**Deployment Flow:**
1. New version deployed with `canary_percent` of traffic
2. System waits for `canary_bake_time_in_minutes`
3. If healthy, remaining traffic shifts to new version
4. If unhealthy, automatic rollback to previous version

### Configuration Options

| Parameter | Default | Description |
|-----------|---------|-------------|
| `canary_bake_time_in_minutes` | `100` | Time to wait and monitor canary before proceeding |
| `canary_percent` | `200` | Percentage of traffic routed to canary (Note: verify valid range with AWS) |

---

## Linear Deployment

Linear deployment shifts traffic incrementally in equal steps over time, providing controlled exposure with validation opportunities at each step.

### Setup

```hcl
gateway_deployment_configuration = {
  enable_blue_green = false
  linear_configuration = {
    step_bake_time_in_minutes = 5    # Wait time between steps
    step_percent              = 20   # Traffic percentage per step (3-100%)
  }
}
```

### How It Works

```
Step 1: 20%        Step 2: 40%        Step 3: 60%        Step 4: 80%        Step 5: 100%
┌──────────┐      ┌──────────┐      ┌──────────┐      ┌──────────┐      ┌──────────┐
│ v1: 80%  │ ──▶  │ v1: 60%  │ ──▶  │ v1: 40%  │ ──▶  │ v1: 20%  │ ──▶  │ v2: 100% │
│ v2: 20%  │      │ v2: 40%  │      │ v2: 60%  │      │ v2: 80%  │      │          │
└──────────┘      └──────────┘      └──────────┘      └──────────┘      └──────────┘
     │                 │                 │                 │
     └─── 5 min ───────┴─── 5 min ───────┴─── 5 min ───────┴─── 5 min ───▶ Complete
           (bake)            (bake)            (bake)            (bake)
```

**Deployment Flow:**
1. Traffic shifts by `step_percent` to new version
2. System waits `step_bake_time_in_minutes`
3. If healthy, next step begins
4. Repeats until 100% traffic on new version
5. If unhealthy at any step, automatic rollback

### Configuration Options

| Parameter | Default | Description |
|-----------|---------|-------------|
| `step_bake_time_in_minutes` | `100` | Wait time between each traffic shift step |
| `step_percent` | `10` | Percentage of traffic to shift per step (3-100%) |

### Example: 25% Steps with 10-minute Bake Time

```hcl
gateway_deployment_configuration = {
  linear_configuration = {
    step_bake_time_in_minutes = 10
    step_percent              = 25
  }
}
```

---

## Deployment Circuit Breaker

All deployment strategies can be enhanced with circuit breaker protection.

### Setup

```hcl
gateway_deployment_circuit_breaker = {
  enable   = true   # Enable circuit breaker
  rollback = true   # Auto-rollback on failure
}
```

### How It Works

1. ECS monitors task health during deployment
2. If tasks fail to stabilize, circuit breaker triggers
3. If `rollback = true`, automatically reverts to previous version
4. Prevents stuck deployments and cascading failures

**Recommendation:** Always enable circuit breaker with rollback in production environments.

---

## Lifecycle Hooks

For advanced deployment control, lifecycle hooks allow custom validation at specific deployment stages.

### Setup

```hcl
gateway_lifecycle_hook = {
  enable_lifecycle_hook = true
  lifecycle_hook_stages = ["RECONCILE_SERVICE", "PRE_SCALE_UP", "PRE_TEST_TRAFFIC_SHIFT"]
}
```

### Available Stages

| Stage | Description |
|-------|-------------|
| `RECONCILE_SERVICE` | Before deployment begins |
| `PRE_SCALE_UP` | Before scaling up new tasks |
| `POST_SCALE_UP` | After new tasks are running |
| `TEST_TRAFFIC_SHIFT` | Before test traffic shift (Blue/Green) |
| `POST_TEST_TRAFFIC_SHIFT` | After test traffic shift |
| `PRODUCTION_TRAFFIC_SHIFT` | Before production traffic shift |
| `POST_PRODUCTION_TRAFFIC_SHIFT` | After production traffic shift |

For more details refer to [AWS Documentation](https://docs.aws.amazon.com/AmazonECS/latest/developerguide/deployment-lifecycle-hooks.html)

### Custom Lambda Function

This project includes a [Lambda function template](../lambda/lifecycle-hook/index.py) that you can customize to implement validation logic:

- Run integration tests
- Check external dependencies
- Implement manual approval gates
- Validate metrics and logs

---

## Strategy Selection Guide

| Requirement | Recommended Strategy |
|-------------|---------------------|
| Simple, standard deployments | Rolling |
| Zero-downtime with instant rollback | Blue/Green |
| High-risk changes, minimal blast radius | Canary |
| Controlled rollout with checkpoints | Linear |
| Fast deployments, acceptable brief downtime | Rolling |
| Compliance requiring validation gates | Blue/Green + Lifecycle Hooks |

## Important Notes

1. **Load Balancer Required:** Blue/Green, Canary, and Linear strategies require `create_lb = true`
2. **Strategy Exclusivity:** Only one advanced strategy (Blue/Green, Canary, or Linear) can be active at a time
3. **Gateway Only:** Advanced deployment strategies are supported only for the Gateway service, not Data Service
4. **Resource Usage:** Blue/Green briefly doubles resource usage during deployment
5. **Test Endpoints:** When advanced strategies are enabled, test endpoints are available on port 8443 (TLS) or 8080 (non-TLS)

## Example Configurations

### Production - Blue/Green with Lifecycle Hooks

```hcl
gateway_deployment_configuration = {
  enable_blue_green = true
}

gateway_deployment_circuit_breaker = {
  enable   = true
  rollback = true
}

gateway_lifecycle_hook = {
  enable_lifecycle_hook = true
  lifecycle_hook_stages = ["PRE_TEST_TRAFFIC_SHIFT", "PRE_PROD_TRAFFIC_SHIFT"]
}
```

### Staging - Canary with Quick Validation

```hcl
gateway_deployment_configuration = {
  canary_configuration = {
    canary_bake_time_in_minutes = 5
    canary_percent              = 10
  }
}

gateway_deployment_circuit_breaker = {
  enable   = true
  rollback = true
}
```

### Development - Simple Rolling

```hcl
gateway_deployment_configuration = null

gateway_deployment_circuit_breaker = {
  enable   = true
  rollback = true
}
```

